-module(jarl_SUITE).

-behaviour(ct_suite).
-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-compile([export_all, nowarn_export_all]).

-import(jarl_test_async, [async_eval/1]).
-import(jarl_test_async, [async_get_result/1]).

-import(jarl_test_server, [flush/0]).
-import(jarl_test_server, [send_text/1]).
-import(jarl_test_server, [send_jsonrpc_request/3]).
-import(jarl_test_server, [send_jsonrpc_notification/2]).
-import(jarl_test_server, [send_jsonrpc_result/2]).
-import(jarl_test_server, [send_jsonrpc_error/3]).


%--- MACROS --------------------------------------------------------------------

% Receive a JSON-RPC request, pattern match method and params, return the id
-define(receiveRequest(Method, Params),
        (fun() ->
                Send = jarl_test_server:receive_jsonrpc_request(),
                ?assertMatch(#{method := Method, params := Params}, Send),
                maps:get(id, Send)
        end)()).

% Receive a JSON-RPC notification, pattern match method and params
-define(receiveNotification(Method, Params),
        (fun() ->
                Send = jarl_test_server:receive_jsonrpc_notification(),
                ?assertMatch(#{method := Method, params := Params}, Send),
                ok
        end)()).

% Receive a JSON-RPC result, pattern match value and id
-define(receiveResult(Value, Id),
        (fun() ->
                Send = jarl_test_server:receive_jsonrpc_result(),
                ?assertMatch(#{result := Value, id := Id}, Send),
                ok
        end)()).

% Receive a JSON-RPC request error, pattern match code, message and id
-define(receiveError(Code, Message, Id),
        (fun() ->
                Send = jarl_test_server:receive_jsonrpc_error(),
                ?assertMatch(#{error := #{code := Code, message := Message}, id := Id}, Send),
                ok
        end)()).

-define(fmt(Fmt, Args), lists:flatten(io_lib:format(Fmt, Args))).
-define(assertConnRequest(Conn, M, P, R), fun() ->
    receive {jarl, Conn, {request, M, P = Result, R}} -> Result
    after 1000 ->
        ?assert(false, ?fmt("The client connection did not receive request ~s ~s ~s; Mailbox: ~p",
                            [??M, ??P, ??P, flush()]))
    end
end()).
-define(assertConnNotification(Conn, M, P), fun() ->
    receive {jarl, Conn, {notification, M, P = Result}} -> Result
    after 1000 ->
        ?assert(false, ?fmt("The client did not receive notification ~s ~s; Mailbox: ~p",
                            [??M, ??P, flush()]))
    end
end()).
-define(assertConnResultResp(Conn, V, X), fun() ->
    receive {jarl, Conn, {response, V = Result, X}} -> Result
    after 1000 ->
        ?assert(false, ?fmt("The client connection did not receive result response ~s ~s; Mailbox: ~p",
                            [??V, ??X, flush()]))
    end
end()).
-define(assertConnErrorResp(Conn, C, M, D, X), fun() ->
    receive {jarl, Conn, {error, C, M, D, X}} -> ok
    after 1000 ->
        ?assert(false, ?fmt("The client connection did not receive error response ~s ~s ~s ~s; Mailbox: ~p",
                            [??C, ??M, ??D, ??X, flush()]))
    end
end()).
-define(assertConnJarlError(Conn, R, X), fun() ->
    receive {jarl, Conn, {jarl_error, R, X}} -> ok
    after 1000 ->
        ?assert(false, ?fmt("The client connection did not receive jarl error ~s ~s; Mailbox: ~p",
                            [??R, ??X, flush()]))
    end
end()).


%--- API -----------------------------------------------------------------------

all() ->
    [
        F
        ||
        {F, 1} <- ?MODULE:module_info(exports),
        lists:suffix("_test", atom_to_list(F))
    ].

init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(gun),
    Apps = jarl_test_server:start("/jarl/ws"),
    [{apps, Apps} | Config].

end_per_suite(Config) ->
    jarl_test_server:stop(?config(apps, Config)).

init_per_testcase(TestCase, Config)
  when TestCase =:= connection_error_test;
       TestCase =:= call_while_connecting_test ->
    Config;
init_per_testcase(_TestCase, Config) ->
    Conn = connect(),
    [{conn, Conn} | Config].

end_per_testcase(TestCase, Config)
  when TestCase =:= connection_error_test;
       TestCase =:= call_while_connecting_test ->
    ?assertEqual([], flush()),
    Config;
end_per_testcase(_TestCase, Config) ->
    Conn = proplists:get_value(conn, Config),
    disconnect(Conn),
    jarl_test_server:wait_disconnection(),
    ?assertEqual([], flush()),
    Config.


%--- Tests ---------------------------------------------------------------------

basic_server_notifications_test(Config) ->
    Conn = proplists:get_value(conn, Config),
    send_jsonrpc_notification(<<"ping">>, #{foo => null}),
    ?assertConnNotification(Conn, [ping], #{foo := undefined}),
    send_jsonrpc_notification(<<"foo.bar.ping">>, #{}),
    ?assertConnNotification(Conn, [foo, bar, ping], _),
    send_jsonrpc_notification(<<"foo.bar.NotAnAtom">>, #{}),
    ?assertConnNotification(Conn, [foo, bar, <<"NotAnAtom">>], _),
    ok.

basic_client_notifications_test(Config) ->
    Conn = proplists:get_value(conn, Config),
    jarl:notify(Conn, ping, #{foo => undefined}),
    ?receiveNotification(<<"ping">>, #{foo := null}),
    jarl:notify(Conn, [foo, bar, ping], #{}),
    ?receiveNotification(<<"foo.bar.ping">>, _),
    jarl:notify(Conn, [foo, bar, <<"NotAnAtom">>], #{}),
    ?receiveNotification(<<"foo.bar.NotAnAtom">>, _),
    ok.

basic_server_request_test(Config) ->
    Conn = proplists:get_value(conn, Config),
    send_jsonrpc_request(<<"toto">>, #{}, 1),
    ?assertConnRequest(Conn, [toto], _, 1),
    jarl:reply(Conn, <<"spam">>, 1),
    ?receiveResult(<<"spam">>, 1),
    send_jsonrpc_request(<<"foo.bar.tata">>, #{}, 2),
    ?assertConnRequest(Conn, [foo, bar, tata], _, 2),
    jarl:reply(Conn, error1, undefined, undefined, 2),
    ?receiveError(-1, <<"Error Number 1">>, 2),
    send_jsonrpc_request(<<"foo.bar.toto">>, #{}, 3),
    ?assertConnRequest(Conn, [foo, bar, toto], _, 3),
    jarl:reply(Conn, error2, <<"Custom">>, undefined, 3),
    ?receiveError(-2, <<"Custom">>, 3),
    send_jsonrpc_request(<<"foo.bar.titi">>, #{}, 4),
    ?assertConnRequest(Conn, [foo, bar, titi], _, 4),
    jarl:reply(Conn, -42, <<"Message">>, undefined, 4),
    ?receiveError(-42, <<"Message">>, 4),
    ok.

basic_client_synchronous_request_test(Config) ->
    Conn = proplists:get_value(conn, Config),
    Async1 = async_eval(fun() -> jarl:request(Conn, [toto], #{}) end),
    Id1 = ?receiveRequest(<<"toto">>, _),
    send_jsonrpc_result(<<"spam">>, Id1),
    ?assertEqual({ok, <<"spam">>}, async_get_result(Async1)),
    Async2 = async_eval(fun() -> jarl:request(Conn, tata, #{}) end),
    Id2 = ?receiveRequest(<<"tata">>, _),
    send_jsonrpc_error(-1, null, Id2),
    ?assertEqual({error, error1, <<"Error Number 1">>, undefined}, async_get_result(Async2)),
    Async3 = async_eval(fun() -> jarl:request(Conn, titi, #{}) end),
    Id3 = ?receiveRequest(<<"titi">>, _),
    send_jsonrpc_error(-2, <<"Custom">>, Id3),
    ?assertEqual({error, error2, <<"Custom">>, undefined}, async_get_result(Async3)),
    ok.

basic_client_asynchronous_request_test(Config) ->
    Conn = proplists:get_value(conn, Config),
    jarl:request(Conn, toto, #{}, ctx1),
    Id1 = ?receiveRequest(<<"toto">>, _),
    send_jsonrpc_result(<<"spam">>, Id1),
    ?assertConnResultResp(Conn, <<"spam">>, ctx1),
    jarl:request(Conn, tata, #{}, ctx2),
    Id2 = ?receiveRequest(<<"tata">>, _),
    send_jsonrpc_error(-1, null, Id2),
    ?assertConnErrorResp(Conn, error1, <<"Error Number 1">>, undefined, ctx2),
    jarl:request(Conn, titi, #{}, ctx3),
    Id3 = ?receiveRequest(<<"titi">>, _),
    send_jsonrpc_error(-2, <<"Custom">>, Id3),
    ?assertConnErrorResp(Conn, error2, <<"Custom">>, undefined, ctx3),
    ok.

request_timeout_test(Config) ->
    Conn = proplists:get_value(conn, Config),
    jarl:request(Conn, toto, #{}, ctx1),
    _Id1 = ?receiveRequest(<<"toto">>, _),
    timer:sleep(500),
    ?assertConnJarlError(Conn, timeout, ctx1),
    ok.

spec_example_test(Config) ->
    DataDir = proplists:get_value(data_dir, Config),
    ExamplesFile = filename:join(DataDir, "jsonrpc_examples.txt"),

    Conn = proplists:get_value(conn, Config),

    {ok, ExData} = file:read_file(ExamplesFile),
    Examples = parse_examples(ExData),
    maps:foreach(fun(Desc, Actions) ->
        try
            lists:foreach(fun
                ({send, Text}) ->
                    send_text(Text);
                ({recv, Expected}) when is_list(Expected) ->
                    example_handler(Conn),
                    SortedExpected = lists:sort(Expected),
                    Received = jarl_test_server:receive_jsonrpc(),
                    ?assert(is_list(Received),
                            ?fmt("Invalid response to a batch request during ~s: ~p",
                                 [Desc, Received])),
                    SortedReceived = lists:sort(Received),
                    ?assertEqual(SortedExpected, SortedReceived,
                                 ?fmt("Invalid response during ~s", [Desc]));
                ({recv, Expected}) ->
                    example_handler(Conn),
                    Received = jarl_test_server:receive_jsonrpc(),
                    ?assertEqual(Expected, Received,
                                 ?fmt("Invalid response during ~s", [Desc]))
            end, Actions),
            example_handler(Conn),
            RemMsgs = flush(),
            ?assertEqual([], RemMsgs,
                         ?fmt("Unexpected message during example ~s: ~p",
                              [Desc, RemMsgs]))
        catch
            error:timeout ->
                ?assert(false, ?fmt("Timeout while testing example ~s", [Desc]))
        end
    end, Examples),

    ok.

calls_after_disconnection_test(Config) ->
    Conn = proplists:get_value(conn, Config),
    disconnect(Conn),
    ?assertMatch({jarl_error, not_connected}, jarl:request(Conn, foo, undefined)),
    ?assertMatch({jarl_error, not_connected}, jarl:request(Conn, foo, undefined, undefined)),
    ?assertMatch({jarl_error, not_connected}, jarl:notify(Conn, foo, undefined)),
    ?assertMatch({jarl_error, not_connected}, jarl:reply(Conn, undefined, 42)),
    ?assertMatch({jarl_error, not_connected}, jarl:reply(Conn, internal_error, undefined, undefined, 42)),
    ?assertMatch(ok, jarl:disconnect(Conn)),
    ok.

call_while_connecting_test(_Config) ->
    ConnOpts = connect_options(#{headers => [{<<"Test-Delay-Upgrade">>, <<"500">>}]}),
    {ok, Conn} = jarl:start_link(self(), ConnOpts),
    ?assertMatch({jarl_error, not_connected}, jarl:request(Conn, foo1, undefined)),
    ?assertMatch({jarl_error, not_connected}, jarl:request(Conn, foo2, undefined, some_ctx)),
    ?assertMatch({jarl_error, not_connected}, jarl:notify(Conn, foo3, undefined)),
    ?assertMatch({jarl_error, not_connected}, jarl:reply(Conn, undefined, 42)),
    ?assertMatch({jarl_error, not_connected}, jarl:reply(Conn, internal_error, undefined, undefined, 42)),
    % A message for the asynchronous request must be sent
    ?assertConnJarlError(Conn, not_connected, some_ctx),
    disconnect(Conn),
    ok.

connection_error_test(_Config) ->
    process_flag(trap_exit, true), % To not die because the connection crashes
    % Test the connection is crashing right away
    ?assertMatch({error, _}, jarl:start_link(self(), #{
        domain => localhost, port => 3030, path => <<"/jarl/ws">>,
        transport => {tls, bad}})),
    % Test the connection cannot be established
    {ok, Conn} = jarl:start_link(self(), connect_options(#{domain => dummy})),
    receive {'EXIT', Conn, _} -> ok after 1000 -> ?assert(false, "Connection did not crash") end,
    ok.


%--- Internal Functions --------------------------------------------------------

connect_options(Opts) ->
    DefaultOpts = #{domain => localhost, port => 3030, transport => tcp,
                    path => <<"/jarl/ws">>,
                    request_timeout => 300,
                    errors => [
                        {error1, -1, <<"Error Number 1">>},
                        {error2, -2, <<"Error Number 2">>}
                    ]},
    maps:merge(DefaultOpts, Opts).

connect() ->
    connect(#{}).

connect(Opts) ->
    ConnOpts = connect_options(Opts),
    {ok, Conn} = jarl:start_link(self(), ConnOpts),
    receive
        {jarl, Conn, connected} ->
            jarl_test_server:listen(),
            Conn
    after
        1000 ->
            ?assert(false, "Connection to test server failed")
    end.

disconnect(Conn) ->
    unlink(Conn),
    MonRef = erlang:monitor(process, Conn),
    jarl:disconnect(Conn),
    receive {'DOWN', MonRef, process, Conn, _} -> ok end.

example_handler(Conn) ->
    receive
        {jarl, Conn, {request, [subtract], [A, B], ReqRef}} ->
            jarl:reply(Conn, A - B, ReqRef),
            example_handler(Conn);
        {jarl, Conn, {request, [subtract], #{minuend := A, subtrahend := B}, ReqRef}} ->
            jarl:reply(Conn, A - B, ReqRef),
            example_handler(Conn);
        {jarl, Conn, {request, [sum], Values, ReqRef}} ->
            Result = lists:foldl(fun(V, Acc) -> V + Acc end, 0, Values),
            jarl:reply(Conn, Result, ReqRef),
            example_handler(Conn);
        {jarl, Conn, {request, [get_data], _, ReqRef}} ->
            jarl:reply(Conn, [<<"hello">>, 5], ReqRef),
            example_handler(Conn);
        {jarl, Conn, {request, _M, _P, ReqRef}} ->
            jarl:reply(Conn, method_not_found, undefined, undefined, ReqRef),
            example_handler(Conn);
        {jarl, Conn, {notification, _M, _P}} ->
            example_handler(Conn);
        {jarl, Conn, {error, _C, _M, _D, _X}} ->
            example_handler(Conn);
        {jarl, Conn, {jarl_error, _R, _X}} ->
            example_handler(Conn)
    after
        100 -> ok
    end.

parse_examples(Data) when is_binary(Data) ->
    Lines = binary:split(Data, <<"\n">>, [global, trim]),
    parse_examples_lines(Lines, #{}, undefined, undefined).

parse_examples_lines([], Acc, undefined, _Actions) ->
    Acc;
parse_examples_lines([], Acc, Desc, Actions) ->
    Acc#{Desc => lists:reverse(Actions)};
parse_examples_lines([<<"-->", RestBin/binary>> | RestLines], Acc, Desc, Actions)
  when Desc =/= undefined ->
    {Raw, RestLines2} = parse_examples_collect([RestBin | RestLines], <<>>),
    parse_examples_lines(RestLines2, Acc, Desc, [{send, Raw} | Actions]);
parse_examples_lines([<<"<--", RestBin/binary>> | RestLines], Acc, Desc, Actions)
  when Desc =/= undefined ->
    case parse_examples_collect([RestBin | RestLines], <<>>) of
        {<<"">>, RestLines2} ->
            parse_examples_lines(RestLines2, Acc, Desc, Actions);
        {Raw, RestLines2} ->
            Decoded = jsx:decode(Raw, [{labels, attempt_atom}, return_maps]),
            parse_examples_lines(RestLines2, Acc, Desc, [{recv, Decoded} | Actions])
    end;
parse_examples_lines([Line | RestLines], Acc, Desc, Actions) ->
    case re:replace(Line, "^\\s+|\\s+$", "", [{return, binary}, global]) of
        <<"">> -> parse_examples_lines(RestLines, Acc, Desc, Actions);
        <<"//", _/binary>> -> parse_examples_lines(RestLines, Acc, Desc, Actions);
        NewDesc ->
            NewAcc = case Desc =/= undefined of
                true -> Acc#{Desc => lists:reverse(Actions)};
                false -> Acc
            end,
            NewDesc2 = re:replace(NewDesc, ":+$", "", [{return, binary}, global]),
            parse_examples_lines(RestLines, NewAcc, NewDesc2, [])
    end.

parse_examples_collect([], Acc) -> {Acc, []};
parse_examples_collect([Line | RestLines], Acc) ->
    case re:replace(Line, "^\\s+|\\s+$", "", [{return, binary}, global]) of
        <<"">> -> {Acc, RestLines};
        <<"-->", _/binary>> -> {Acc, [Line | RestLines]};
        <<"<--", _/binary>> -> {Acc, [Line | RestLines]};
        <<"//", _/binary>> -> parse_examples_collect(RestLines, Acc);
        Line2 -> parse_examples_collect(RestLines, <<Acc/binary, Line2/binary>>)
    end.
