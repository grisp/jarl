-module(jarl_jsonrpc_SUITE).

-include_lib("stdlib/include/assert.hrl").

-compile([export_all, nowarn_export_all]).

all() -> [
    positional_parameters,
    named_parameters,
    using_existing_atoms,
    notification,
    invalid_json,
    invalid_request,
    batch,
    result,
    null_values,
    error_data,
    omitted_params,
    encoding_error
].


positional_parameters(_) ->
    Term = {request, <<"subtract">>, [42,23], 1},
    Json = <<"{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,23]}">>,
    ?assertMatch(Term, jarl_jsonrpc:decode(Json)),
    Json2 = jarl_jsonrpc:encode(Term),
    ?assert(jsonrpc_check([<<"\"id\":1">>,
                           <<"\"method\":\"subtract\"">>,
                           <<"\"params\":[42,23]">>], Json2)).

named_parameters(_) ->
    Term = {request, <<"divide">>, #{<<"dividend">> => 42, <<"divisor">> => 2}, 2},
    Json = <<"{\"id\":2,\"jsonrpc\":\"2.0\",\"method\":\"divide\",\"params\":{\"dividend\":42,\"divisor\":2}}">>,
    ?assertMatch(Term, jarl_jsonrpc:decode(Json)),
    Json2 = jarl_jsonrpc:encode(Term),
    ?assert(jsonrpc_check([<<"\"id\":2">>,
                           <<"\"method\":\"divide\"">>,
                           <<"\"dividend\":42">>,
                           <<"\"divisor\":2">>], Json2)).

using_existing_atoms(_) ->
    % The ID and method are matching existing atoms, checks they are not atoms
    Term = {request, <<"notification">>, #{}, <<"request">>},
    Json = <<"{\"id\":\"request\",\"jsonrpc\":\"2.0\",\"method\":\"notification\",\"params\":{}}">>,
    ?assertMatch(Term, jarl_jsonrpc:decode(Json)),
    Json2 = jarl_jsonrpc:encode(Term),
    ?assert(jsonrpc_check([<<"\"id\":\"request\"">>, <<"\"method\":\"notification\"">>], Json2)).

notification(_) ->
    Term = {notification, <<"update">>, [1,2,3,4,5, 3.14]},
    Json = <<"{\"jsonrpc\":\"2.0\",\"method\":\"update\",\"params\":[1,2,3,4,5,3.14]}">>,
    ?assertMatch(Term, jarl_jsonrpc:decode(Json)),
    Json2 = jarl_jsonrpc:encode(Term),
    ?assert(jsonrpc_check([<<"\"method\":\"update\"">>,
                           <<"\"params\":[1,2,3,4,5,3.14]">>], Json2)).

invalid_json(_) ->
    Term = {decoding_error, -32700, <<"Parse error">>, undefined, undefined},
    Json = <<"{\"jsonrpc\":\"2.0\",\"method\":\"foobar,\"params\":\"bar\",\"baz]">>,
    ?assertMatch(Term, jarl_jsonrpc:decode(Json)),
    JsonError = jarl_jsonrpc:encode(Term),
    ?assert(jsonrpc_check([<<"\"error\":{">>,
                            <<"\"code\":-32700">>,
                            <<"\"message\":\"Parse error\"">>,
                            <<"\"id\":null">>], JsonError)).

invalid_request(_) ->
    Term1 = {decoding_error, -32600, <<"Invalid Request">>, undefined, undefined},
    JsonIn1 = <<"{\"jsonrpc\":\"2.0\",\"method\":1,\"params\":\"bar\"}">>,
    ?assertMatch(Term1, jarl_jsonrpc:decode(JsonIn1)),
    JsonOut1 = jarl_jsonrpc:encode(Term1),
    ?assert(jsonrpc_check([<<"\"error\":{">>,
                           <<"\"code\":-32600">>,
                           <<"\"message\":\"Invalid Request\"">>,
                           <<"\"id\":null">>], JsonOut1)),
    Term2 = {decoding_error, -32600, <<"Invalid Request">>, undefined, 33},
    JsonIn2 = <<"{\"id\":33,\"jsonrpc\":\"2.0\",\"method\":1,\"params\":\"bar\"}">>,
    ?assertMatch(Term2, jarl_jsonrpc:decode(JsonIn2)),
    JsonOut2 = jarl_jsonrpc:encode(Term2),
    ?assert(jsonrpc_check([<<"\"error\":{">>,
                            <<"\"code\":-32600">>,
                            <<"\"message\":\"Invalid Request\"">>,
                            <<"\"id\":33">>], JsonOut2)).

batch(_) ->
    Term1 = {request, <<"sum">>, [1,2,4], <<"1">>},
    Term2 = {decoding_error, -32600, <<"Invalid Request">>, undefined, undefined},
    Json = <<"[{\"jsonrpc\":\"2.0\",\"method\":\"sum\",\"params\":[1,2,4],\"id\":\"1\"},{\"foo\":\"boo\"}]">>,
    ?assertMatch([Term1, Term2], jarl_jsonrpc:decode(Json)),
    JsonError = jarl_jsonrpc:encode([Term1, Term2]),
    ?assert(jsonrpc_check([<<"\"id\":\"1\"">>,
                           <<"\"method\":\"sum\"">>,
                           <<"\"params\":[1,2,4]">>,
                           <<"\"error\":{">>,
                           <<"\"code\":-32600">>,
                           <<"\"message\":\"Invalid Request\"">>,
                           <<"\"id\":null">>], JsonError)).

result(_) ->
    Term = {result, 7, 45},
    Json = <<"{\"id\":45,\"jsonrpc\":\"2.0\",\"result\":7}">>,
    ?assertMatch(Term, jarl_jsonrpc:decode(Json)),
    Json2 = jarl_jsonrpc:encode(Term),
    ?assert(jsonrpc_check([<<"\"id\":45">>,
                           <<"\"result\":7">>], Json2)).

null_values(_) ->
    Term = {notification, <<"test_null">>, #{array => [undefined], object => #{foo => undefined}, value => undefined}},
    Json = <<"{\"jsonrpc\":\"2.0\",\"method\":\"test_null\",\"params\":{\"array\":[null],\"object\":{\"foo\":null},\"value\":null}}">>,
    ?assertMatch(Term, jarl_jsonrpc:decode(Json)),
    Json2 = jarl_jsonrpc:encode(Term),
    ?assert(jsonrpc_check([<<"\"array\":[null]">>,
                           <<"\"foo\":null">>,
                           <<"\"value\":null">>],
                          Json2)).

error_data(_) ->
    Term = {error, 123, <<"FooBar">>, <<"Some extra data">>, 42},
    Json = <<"{\"id\":42,\"jsonrpc\":\"2.0\",\"error\":{\"code\":123,\"message\":\"FooBar\",\"data\":\"Some extra data\"}}">>,
    ?assertMatch(Term, jarl_jsonrpc:decode(Json)),
    Json2 = jarl_jsonrpc:encode(Term),
    ?assert(jsonrpc_check([<<"\"error\":{">>,
                           <<"\"id\":42">>,
                           <<"\"code\":123">>,
                           <<"\"message\":\"FooBar\"">>,
                           <<"\"data\":\"Some extra data\"">>], Json2)).

omitted_params(_) ->
    Term1 = {request, <<"foo">>, undefined, 42},
    JsonIn1 = <<"{\"id\":42,\"jsonrpc\":\"2.0\",\"method\":\"foo\"}">>,
    ?assertMatch(Term1, jarl_jsonrpc:decode(JsonIn1)),
    JsonOut1 = jarl_jsonrpc:encode(Term1),
    ?assert(jsonrpc_check([<<"\"id\":42">>,
                           <<"\"method\":\"foo\"">>], JsonOut1)),
    ?assert(binary:match(<<"params">>, JsonOut1) =:= nomatch),
    Term2 = {notification, <<"foo">>, undefined},
    JsonIn2 = <<"{\"jsonrpc\":\"2.0\",\"method\":\"foo\"}">>,
    ?assertMatch(Term2, jarl_jsonrpc:decode(JsonIn2)),
    JsonOut2 = jarl_jsonrpc:encode(Term2),
    ?assert(jsonrpc_check([<<"\"method\":\"foo\"">>], JsonOut2)),
    ?assert(binary:match(<<"params">>, JsonOut2) =:= nomatch).

encoding_error(_) ->
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode(foobar)),
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode({request, [], [], 42})),
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode({request, 33, [], 42})),
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode({request, <<"foo">>, <<"bar">>, 42})),
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode({request, "foo", [], 42})),
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode({request, <<"foo">>, [], undefined})),
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode({notification, [], []})),
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode({notification, 33, []})),
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode({notification, "foo", []})),
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode({notification, <<"foo">>, <<"bar">>})),
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode({result, <<"ok">>, undefined})),
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode({error, atom, undefined, undefined, 42})),
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode({error, 123, 456, undefined, 42})),
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode({error, 123, undefined, 123, 42})),
    ?assertException(error, {badarg, _}, jarl_jsonrpc:encode({error, 123, undefined, undefined, atom})),
    ok.

jsonrpc_check(Elements, JsonString) ->
    Elements2 = [<<"\"jsonrpc\":\"2.0\"">>| Elements],
    lists:all(fun(E) -> binary:match(JsonString, E) =/= nomatch end, Elements2).
