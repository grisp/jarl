-module(jarl_jsonrpc).

% API
-export([decode/1]).
-export([encode/1]).


%--- Types ---------------------------------------------------------------------

-type json_rpc_message() ::
    {request, Method :: binary(), Params :: map() | list(),
     ReqRef :: binary() | integer()}
  | {result, Result :: term(), ReqRef :: binary()}
  | {notification, Method :: binary(), Params :: map() | list()}
  | {error, Code :: integer(), Message :: undefined | binary(),
     Data :: undefined | term(), ReqRef :: undefined | binary() | integer()}
  | {decoding_error, Code :: integer(), Message :: undefined | binary(),
     Data :: undefined | term(), ReqRef :: undefined | binary() | integer()}.



%--- Macros --------------------------------------------------------------------

-define(V, jsonrpc => <<"2.0">>).
-define(is_valid(Message),
    (map_get(jsonrpc, Message) == <<"2.0">>)
).
-define(is_params(Params),
    (is_map(Params) orelse is_list(Params))
).
-define(is_id(ID),
    (is_binary(ID) orelse is_integer(ID))
).


%--- API -----------------------------------------------------------------------

%% @doc Decode a JSONRpc text packet and decoded message or a list of decoded
%% messages in the case of a batch.
%%
%% If it returns a list, the all the responses are supposed to be sent back in
%% a batch too, as per the JSONRpc 2.0 specifications.
%%
%% If some decoding errors occure, a special error message with the tag
%% `decoding_error' will be returned, this message can be encoded and sent back
%% directly to the JSON-RPC peer.
%%
%% During JSON decoding, the `null' values are changed to `undefined' and when
%% encoding, `undefined' values are changed back to `null'.
%%
%% The `method' will <b>always</b> be a binary, and `id' will always be either
%% a binary or an integer.
%%
%% <p>The possible decoded messages are:
%% <ul>
%%     <li><b>`{request, Method :: binary(), Params :: map() | list(), ReqRef :: binary() | integer()}'</b></li>
%%     <li><b>`{result, Result :: term(), ReqRef :: binary()}'</b></li>
%%     <li><b>`{notification, Method :: binary(), Params :: map() | list()}'</b></li>
%%     <li><b>`{error, Code :: integer(), Message :: undefined | binary(), Data :: undefined | term(), ReqRef :: undefined | binary() | integer()}'</b></li>
%%     <li><b>`{decoding_error, Code :: integer(), Message :: undefined | binary(), Data :: undefined | term(), ReqRef :: undefined | binary() | integer()}'</b></li>
%% </ul></p>
-spec decode(Data :: iodata()) -> json_rpc_message() | [json_rpc_message()].
decode(Data) ->
    case json_to_term(iolist_to_binary(Data)) of
        [] ->
            {decoding_error, -32600, <<"Invalid Request">>, undefined, undefined};
        Messages when is_list(Messages) ->
            [unpack(M) || M <- Messages];
        Message when is_map(Message) ->
            unpack(Message);
        {error, _Reason} ->
            % Even though the data could have been a batch, we return a single
            % error, as per JSON-RPC specifications
            {decoding_error, -32700, <<"Parse error">>, undefined, undefined}
    end.

%% @doc Encode a JSONRpc message or a list of JSONRpc messages to JSON text.
%% For backward compatibility, the `method' can be an atom.
-spec encode(Messages :: json_rpc_message() | [json_rpc_message()]) -> iodata().
encode(Messages) when is_list(Messages) ->
    term_to_json([pack(M) || M <- Messages]);
encode(Message) ->
    term_to_json(pack(Message)).


%--- Internal ------------------------------------------------------------------

unpack(#{method := Method, params := Params, id := ID} = M)
  when ?is_valid(M), is_binary(Method), ?is_params(Params), ?is_id(ID) ->
    {request, Method, Params, ID};
unpack(#{method := Method, id := ID} = M)
  when ?is_valid(M), is_binary(Method), ?is_id(ID) ->
    {request, Method, undefined, ID};
unpack(#{method := Method, params := Params} = M)
  when ?is_valid(M), is_binary(Method), ?is_params(Params) ->
    {notification, Method, Params};
unpack(#{method := Method} = M)
  when ?is_valid(M), is_binary(Method) ->
    {notification, Method, undefined};
unpack(#{result := Result, id := ID} = M)
  when ?is_valid(M), ?is_id(ID) ->
    {result, Result, ID};
unpack(#{error := #{code := Code, message := Message, data := Data},
         id := ID} = M)
  when ?is_valid(M), is_integer(Code), ?is_id(ID) orelse ID =:= undefined,
       (is_binary(Message) orelse Message =:= undefined) ->
    {error, Code, Message, Data, ID};
unpack(#{error := #{code := Code, message := Message}, id := ID} = M)
  when ?is_valid(M), is_integer(Code), ?is_id(ID) orelse ID =:= undefined,
       (is_binary(Message) orelse Message =:= undefined) ->
    {error, Code, Message, undefined, ID};
unpack(#{id := ID}) ->
    {decoding_error, -32600, <<"Invalid Request">>, undefined, ID};
unpack(_M) ->
    {decoding_error, -32600, <<"Invalid Request">>, undefined, undefined}.

pack({request, Method, undefined, ID})
  when is_binary(Method) orelse is_atom(Method), ?is_id(ID) ->
    #{?V, method => Method, id => ID};
pack({request, Method, Params, ID})
  when is_binary(Method) orelse is_atom(Method),
       Params =:= undefined orelse ?is_params(Params),
       ?is_id(ID) ->
    #{?V, method => Method, params => Params, id => ID};
pack({notification, Method, undefined})
  when is_binary(Method) orelse is_atom(Method) ->
    #{?V, method => Method};
pack({notification, Method, Params})
  when is_binary(Method), Params =:= undefined orelse ?is_params(Params) ->
    #{?V, method => Method, params => Params};
pack({result, Result, ID})
  when ?is_id(ID) ->
    #{?V, result => Result, id => ID};
pack({ErrorTag, Code, Message, undefined, undefined})
  when ErrorTag =:= error orelse ErrorTag =:= decoding_error, is_integer(Code),
       Message =:= undefined orelse is_binary(Message) ->
    #{?V, error => #{code => Code, message => Message}, id => null};
pack({ErrorTag, Code, Message, undefined, ID})
  when ErrorTag =:= error orelse ErrorTag =:= decoding_error, is_integer(Code),
       Message =:= undefined orelse is_binary(Message), ?is_id(ID) ->
    #{?V, error => #{code => Code, message => Message}, id => ID};
pack({ErrorTag, Code, Message, Data, ID})
  when ErrorTag =:= error orelse ErrorTag =:= decoding_error, is_integer(Code),
       Message =:= undefined orelse is_binary(Message), ?is_id(ID),
       is_binary(Data) ->
    #{?V, error => #{code => Code, message => Message, data => Data}, id => ID};
pack(Message) ->
    erlang:error({badarg, Message}).

json_to_term(Bin) ->
    try jsx:decode(Bin, [{labels, attempt_atom}, return_maps]) of
        Json -> postprocess(Json)
    catch
        error:E -> {error, E}
    end.

term_to_json(Term) ->
    jsx:encode(preprocess(Term)).

postprocess(null) -> undefined;
postprocess(Integer) when is_integer(Integer) -> Integer;
postprocess(Boolean) when is_boolean(Boolean) -> Boolean;
postprocess(Float) when is_float(Float) -> Float;
postprocess(Binary) when is_binary(Binary) -> Binary;
postprocess(List) when is_list(List) ->
    [postprocess(E) || E <- List];
postprocess(Map) when is_map(Map) ->
    maps:map(fun(_K, V) -> postprocess(V) end, Map).

preprocess(undefined) -> null;
preprocess(Atom) when is_atom(Atom) -> Atom;
preprocess(Integer) when is_integer(Integer) -> Integer;
preprocess(Float) when is_float(Float) -> Float;
preprocess(Binary) when is_binary(Binary) -> Binary;
preprocess(List) when is_list(List) ->
    [preprocess(E) || E <- List];
preprocess(Map) when is_map(Map) ->
    maps:map(fun(_K, V) -> preprocess(V) end, Map);
preprocess(_Term) ->
    erlang:error(badarg).
