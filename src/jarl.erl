-module(jarl).

% API Functions
-export([start_link/2]).
-export([request/3, request/4]).
-export([notify/3]).
-export([reply/3, reply/5]).
-export([disconnect/1]).


%--- Types ---------------------------------------------------------------------

-type error_mapping() :: {atom(), integer(), binary()}.
-type method() :: atom() | binary() | [atom() | binary()].
-type start_options() :: #{
    domain := atom() | string() | binary(),
    port := inet:port_number(),
    %FIXME: dialyzer does not like ssl:tls_client_option(), maybe some Erlang version issue
    transport := tcp | tls | {tls, TlsOpts :: list()},
    path := atom() | string() | binary(),
    errors => [error_mapping()],
    ping_timeout => infinity | pos_integer(),
    request_timeout => infinity | pos_integer(),
    headers => [{binary(), iodata()}],
    protocols => [binary()]
}.
-type jarl_error_reason() :: not_connected | timeout | closed.

% Type specification of the messages that are sent to the handler process:
-type handler_messages() ::
    % Received when the client is connected and ready to handle requests:
    {jarl, pid(), {connected, Headers :: [{binary(), iodata()}]}}
    % Received when the JSON-RPC server sent a request:
  | {jarl, pid(), {request, method(), Params :: map() | list(), ReqRef :: binary() | integer()}}
    % Received when the JSON-RPC server sent a notification:
  | {jarl, pid(), {notification, method(), Params :: map() | list()}}
    % Received when the JSON-RPC server replied to a request with a result:
  | {jarl, pid(), {result, Result :: term(), Ctx :: term()}}
    % Received when the JSON-RPC server replied to a request with an error:
  | {jarl, pid(), {error, Code :: integer() | atom(), Message :: undefined | binary(), ErData :: term(), Ctx :: term()}}
    % Received when a request failed without a response from the JSON-RPC server:
  | {jarl, pid(), {jarl_error, Reason :: jarl_error_reason(), Ctx :: term()}}.

-export_type([
    error_mapping/0,
    method/0,
    jarl_error_reason/0,
    handler_messages/0,
    start_options/0
]).


%--- API Functions -------------------------------------------------------------

% @doc Starts a new JSON-RPC client connection process and links it to the calling process.
-spec start_link(Handler :: pid(), Options :: start_options()) ->
    {ok, Conn :: pid()} | {error, Reason :: term()}.
start_link(Handler, Opts) ->
    jarl_connection:start_link(Handler, Opts).

% @doc Sends a synchronous request to the JSON-RPC server.
-spec request(Conn :: pid(), Method :: method(), Params :: map()) ->
    {result, Result :: term()}
  | {error, Code :: integer(), Message :: undefined | binary(), ErData :: term()}
  | {jarl_error, Reason :: jarl_error_reason()}.
request(Conn, Method, Params) ->
    jarl_connection:request(Conn, Method, Params).

% @doc Sends an asynchronous request to the JSON-RPC server.
% The request is sent without waiting for a response.
% It may return an error if the connection is not established and the request
% couldn't be sent, but the handler will receive the jarl_error message anyway.
-spec request(Conn :: pid(), Method :: method(), Params :: map(),
           ReqCtx :: term()) ->
    ok | {jarl_error, Reason :: jarl_error_reason()}.
request(Conn, Method, Params, ReqCtx) ->
    jarl_connection:request(Conn, Method, Params, ReqCtx).

% @doc Sends a notification to the JSON-RPC server.
% It may return an error if the connection is not established and the request
% couldn't be sent.
-spec notify(Conn :: pid(), Method :: method(), Params :: map()) ->
    ok | {jarl_error, not_connected}.
notify(Conn, Method, Params) ->
    jarl_connection:notify(Conn, Method, Params).

% @doc Sends a result response to a JSON-RPC request.
% It may return an error if the connection is not established and the response
% couldn't be sent.
-spec reply(Conn :: pid(), Result :: any(), ReqRef :: binary()) ->
    ok | {jarl_error, not_connected}.
reply(Conn, Result, ReqRef) ->
    jarl_connection:reply(Conn, Result, ReqRef).

% @doc Sends an error response to a JSON-RPC request.
% It may return an error if the connection is not established and the response
% couldn't be sent.
-spec reply(Conn :: pid(), Code :: atom() | integer(),
            Message :: undefined | binary(), ErData :: term(),
            ReqRef :: undefined | binary()) ->
    ok | {jarl_error, not_connected}.
reply(Conn, Code, Message, ErData, ReqRef) ->
    jarl_connection:reply(Conn, Code, Message, ErData, ReqRef).

% @doc Disconnects the client from the JSON-RPC server.
% The handler will receive a jarl_error message for all pending requests.
-spec disconnect(Conn :: pid()) -> ok.
disconnect(Conn) ->
    jarl_connection:disconnect(Conn).
