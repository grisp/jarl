-module(jarl_test_server).

-behaviour(cowboy_websocket).

-include_lib("stdlib/include/assert.hrl").

%--- Exports -------------------------------------------------------------------

% API functions
-export([start/1, start/2]).
-export([stop/1]).
-export([start_cowboy/2]).
-export([stop_cowboy/0]).
-export([close_websocket/0]).
-export([listen/0]).
-export([flush/0]).
-export([receive_text/0, receive_text/1]).
-export([receive_jsonrpc/0, receive_jsonrpc/1]).
-export([receive_jsonrpc_request/0, receive_jsonrpc_request/1]).
-export([receive_jsonrpc_notification/0]).
-export([receive_jsonrpc_result/0]).
-export([receive_jsonrpc_error/0]).
-export([send_text/1]).
-export([send_frame/1]).
-export([send_jsonrpc_notification/2]).
-export([send_jsonrpc_request/3]).
-export([send_jsonrpc_result/2]).
-export([send_jsonrpc_error/3]).
-export([wait_disconnection/0]).

% Websocket Callbacks
-export([init/2]).
-export([websocket_init/1]).
-export([websocket_handle/2]).
-export([websocket_info/2]).


%--- API Functions -------------------------------------------------------------

% Start the cowboy application and server,
% call this in `init_per_suite'.
% Returns the started apps
start(Path) ->
    start(Path, #{}).

start(Path, ServerOpts) ->
    {ok, Apps} = application:ensure_all_started(cowboy),
    start_cowboy(Path, ServerOpts),
    Apps.

stop(Apps) ->
    ?assertEqual(ok, stop_cowboy()),
    [?assertEqual(ok, application:stop(App)) || App <- Apps],
    % Ensure the process is unregistered...
    wait_disconnection().


% Start the cowboy listener.
% You have to make sure cowboy is running before.
start_cowboy(Path, ServerOpts) ->
    Dispatch = cowboy_router:compile(
        [{'_', [{Path, jarl_test_server, ServerOpts}]}]),
    {ok, _} = cowboy:start_clear(server_listener, [{port, 3030}],
                                 #{env => #{dispatch => Dispatch}}).

% Stop the cowboy listener.
stop_cowboy() ->
    cowboy:stop_listener(server_listener).

% Close the websocket.
close_websocket() ->
    ?MODULE ! ?FUNCTION_NAME.

% Listen to websocket messages.
% Call this in `init_per_testcase' after connecting to the websocket
listen() ->
    ?MODULE ! {?FUNCTION_NAME, self()},
    receive ok -> ok
    after 5000 -> {error, timeout}
    end.

% Flush all messages.
% Call this in `end_per_testcase` to see what messages where missed.
% This is especially useful when test cases fail.
flush() -> flush([]).

flush(Acc) ->
    receive Any -> ct:pal("Flushed: ~p", [Any]), flush([Any | Acc])
    after 0 -> lists:reverse(Acc)
    end.

receive_text() ->
    receive_text(5000).

receive_text(Timeout) ->
    receive {received_text, Msg} -> Msg
    after Timeout -> error(timeout)
    end.

receive_jsonrpc() ->
    check_jsonrpc(receive_text()).

receive_jsonrpc(Timeout) ->
    check_jsonrpc(receive_text(Timeout)).

receive_jsonrpc_request() ->
    case receive_jsonrpc() of
        #{id := _} = Decoded -> Decoded;
        Decoded -> error({invalid_jsonrpc_request, Decoded})
    end.

receive_jsonrpc_request(Timeout) ->
    case receive_jsonrpc(Timeout) of
        #{id := _} = Decoded -> Decoded;
        Decoded -> error({invalid_jsonrpc_request, Decoded})
    end.

receive_jsonrpc_notification() ->
    case receive_jsonrpc() of
        #{method := _} = Decoded -> Decoded;
        Decoded -> error({invalid_jsonrpc_notification, Decoded})
    end.

receive_jsonrpc_result() ->
    case receive_jsonrpc() of
        #{result := _} = Decoded -> Decoded;
        Decoded -> error({invalid_jsonrpc_result, Decoded})
    end.

receive_jsonrpc_error() ->
    case receive_jsonrpc() of
        #{error := _} = Decoded -> Decoded;
        Decoded -> error({invalid_jsonrpc_error, Decoded})
    end.

check_jsonrpc(Msg) ->
    case jsx:decode(Msg, [{labels, attempt_atom}, return_maps]) of
        #{jsonrpc := <<"2.0">>} = Decoded -> Decoded;
        Batch when is_list(Batch) ->
            lists:foreach(fun
                (#{jsonrpc := <<"2.0">>}) -> ok;
                (_) -> error({invalid_jsonrpc, Msg})
            end, Batch),
            Batch;
        _ -> error({invalid_jsonrpc, Msg})
    end.

send_text(Msg) ->
    send_frame({text, Msg}).

send_frame(Frame) ->
    ?MODULE ! {?FUNCTION_NAME, Frame}.

send_jsonrpc_notification(Method, Params) ->
    Map = #{jsonrpc => <<"2.0">>,
            method => Method,
            params => Params},
    send_text(jsx:encode(Map)).

send_jsonrpc_request(Method, Params, Id) ->
    Map = #{jsonrpc => <<"2.0">>,
            method => Method,
            params => Params,
            id => Id},
    send_text(jsx:encode(Map)).

send_jsonrpc_result(Result, Id) ->
    Map = #{jsonrpc => <<"2.0">>,
            result => Result,
            id => Id},
    send_text(jsx:encode(Map)).

send_jsonrpc_error(Code, Msg, Id) ->
    Map = #{jsonrpc => <<"2.0">>,
            error => #{code => Code, message => Msg},
            id => Id},
    send_text(jsx:encode(Map)).

wait_disconnection() ->
    case whereis(?MODULE) of
        undefined -> ok;
        _Pid ->
            timer:sleep(200),
            wait_disconnection()
    end.


%--- Websocket Callbacks -------------------------------------------------------

init(Req, Opts) ->
    case cowboy_req:header(<<"test-delay-upgrade">>, Req) of
        undefined -> ok;
        Value ->
            Delay = binary_to_integer(Value),
            timer:sleep(Delay)
    end,
    case cowboy_req:header(<<"test-upgrade-error">>, Req) of
        undefined ->
            {cowboy_websocket, Req, Opts};
        Reason ->
            {stop, Reason}
    end.

websocket_init(State) ->
    register(?MODULE, self()),
    schedule_ping(State),
    {[], []}.

websocket_handle({text, Msg}, State) ->
    ct:pal("Received websocket message:~n~s", [Msg]),
    [Pid ! {received_text, Msg} || Pid <- State],
    {[], State};
websocket_handle(Frame, State) ->
    ct:pal("Ignore websocket frame:~n~p", [Frame]),
    {[], State}.

websocket_info({listen, Pid}, State) ->
    Pid ! ok,
    {[], [Pid | State]};
websocket_info(send_ping, State) ->
    schedule_ping(State),
    {[ping], State};
websocket_info({send_frame, Frame}, State) ->
    {[Frame], State};
websocket_info(close_websocket, State) ->
    {[close], State};
websocket_info(Info, State) ->
    ct:pal("Ignore websocket info:~n~p", [Info]),
    {[], State}.

schedule_ping(#{ping_interval := Interval}) ->
    erlang:send_after(Interval, ?MODULE, send_ping);
schedule_ping(_) ->
    ok.
