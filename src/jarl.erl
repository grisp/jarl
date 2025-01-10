-module(jarl).

% API Functions
-export([start_link/2]).
-export([request/3]).
-export([post/4]).
-export([notify/3]).
-export([reply/3]).
-export([error/5]).
-export([disconnect/1]).


%--- Types ---------------------------------------------------------------------

-type error_mapping() :: {atom(), integer(), binary()}.
-type method() :: atom() | binary() | [atom() | binary()].
-type start_options() :: #{
    domain := atom() | string() | binary(),
    port := inet:port_number(),
    %FIXME: dialyzer do no like ssl:tls_client_option(), maybe some erlang version issue
    transport := tcp | tls | {tls, TlsOpts :: list()},
    path := atom() | string() | binary(),
    errors => [error_mapping()],
    ping_timeout => infinity | pos_integer(),
    request_timeout => infinity | pos_integer()
}.

% Type specfication of the messages that are sent to the handler:
-type handler_messages() ::
    {conn, pid(), connected}
  | {conn, pid(), {request, method(), Params :: map() | list(), ReqRef :: binary() | integer()}}
  | {conn, pid(), {notification, method(), Params :: map() | list()}}
  | {conn, pid(), {response, Result :: term(), Ctx :: term()}}
  | {conn, pid(), {remote_error, Code :: integer() | atom(), Message :: undefined | binary(), ErData :: term()}}
  | {conn, pid(), {remote_error, Code :: integer() | atom(), Message :: undefined | binary(), ErData :: term(), Ctx :: term()}}
  | {conn, pid(), {local_error, Reason:: atom(), Ctx :: term()}}.

-export_type([error_mapping/0, method/0, handler_messages/0, start_options/0]).


%--- API Functions -------------------------------------------------------------

-spec start_link(Handler :: pid(), Options :: start_options()) ->
    {ok, Conn :: pid()} | {error, Reason :: term()}.
start_link(Handler, Opts) ->
    jarl_connection:start_link(Handler, Opts).

-spec request(Conn :: pid(), Method :: method(), Params :: map()) ->
    {ok, Result :: term()} | {error, timeout} | {error, not_connected}
    | {error, Code :: integer(),
              Message :: undefined | binary(), ErData :: term()}.
request(Conn, Method, Params) ->
    jarl_connection:request(Conn, Method, Params).

-spec post(Conn :: pid(), Method :: method(), Params :: map(),
           ReqCtx :: term()) -> ok | {error, not_connected}.
post(Conn, Method, Params, ReqCtx) ->
    jarl_connection:post(Conn, Method, Params, ReqCtx).

-spec notify(Conn :: pid(), Method :: method(), Params :: map()) ->
    ok | {error, not_connected}.
notify(Conn, Method, Params) ->
    jarl_connection:notify(Conn, Method, Params).

-spec reply(Conn :: pid(), Result :: any(), ReqRef :: binary()) ->
    ok | {error, not_connected}.
reply(Conn, Result, ReqRef) ->
    jarl_connection:reply(Conn, Result, ReqRef).

-spec error(Conn :: pid(), Code :: atom() | integer(),
            Message :: undefined | binary(), ErData :: term(),
            ReqRef :: undefined | binary()) ->
    ok | {error, not_connected}.
error(Conn, Code, Message, ErData, ReqRef) ->
    jarl_connection:error(Conn, Code, Message, ErData, ReqRef).

-spec disconnect(Conn :: pid()) -> ok.
disconnect(Conn) ->
    jarl_connection:disconnect(Conn).
