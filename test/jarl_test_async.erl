%% @doc Helper function for asynchronous function calls
%% @end

-module(jarl_test_async).

%--- Exports -------------------------------------------------------------------

% API Functions
-export([async_eval/1]).
-export([async_get_result/1]).


%--- API Functions -------------------------------------------------------------

async_eval(Fun) ->
    spawn_link(
      fun() ->
        Res = try Fun() of
            R -> {result, R}
        catch
            C:R:S -> {exception, {C, R, S}}
        end,
        receive
            {'$async_get_result', Pid} -> Pid ! {'$async_result', Res}
        end
      end).

async_get_result(Pid) ->
    MRef = monitor(process, Pid),
    unlink(Pid),
    Pid ! {'$async_get_result', self()},
    receive
        {'$async_result', Res} ->
            receive {'DOWN', MRef, process, Pid, normal} -> ok
            after 10 -> error({timeout, waiting_exit})
            end,
            case Res of
                {result, R} -> R;
                {exception, {C, R, S}} -> erlang:raise(C, R, S)
            end;
        {'DOWN', MRef, process, Pid, Reason} ->
            error({process_down, Reason})
    after 1000 ->
            error({timeout, waiting_result})
    end.
