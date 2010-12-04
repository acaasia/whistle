%%%-------------------------------------------------------------------
%%% @author Karl Anderson <karl@2600hz.com>
%%% @copyright (C) 2010, Karl Anderson
%%% @doc
%%% Responsible for managing the monitoring application
%%% @end
%%% Created : 11 Nov 2010 by Karl Anderson <karl@2600hz.com>
%%%-------------------------------------------------------------------
-module(monitor_job).

-behaviour(gen_server).

%% API
-export([start_link/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
     terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_INTERVAL, 10000).

-import(logger, [format_log/3]).
-import(proplists, [get_value/2, get_value/3]).

-include("../include/monitor_amqp.hrl").

-record(state, {
         amqp_host = "" :: string()
        ,job_id = "" :: string()
        ,tref
        ,tasks = []
        ,iteration = 0
        ,interval = ?DEFAULT_INTERVAL
    }).

-record(task, {
         type = "" :: string()
        ,options = []
    }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Job_ID, Tasks, AHost) ->
    gen_server:start_link(?MODULE, [monitor_util:to_list(Job_ID), Tasks, AHost], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Job_ID, Tasks, AHost]) ->
    format_log(info, "MONITOR_JOB(~p): Starting new job with id ~p and amqp host ~p~n", [self(), Job_ID, AHost]),
    {ok, TRef} = timer:send_interval(?DEFAULT_INTERVAL, {heartbeat}),
    {ok, #state{amqp_host=AHost, job_id=Job_ID, tref=TRef, tasks=Tasks}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({set_amqp_host, AHost}, _From, #state{amqp_host=CurrentAHost}=State) ->
    format_log(info, "MONITOR_JOB(~p): Updating amqp host from ~p to ~p~n", [self(), CurrentAHost, AHost]),
    {reply, amqp_host_updated, State#state{amqp_host=AHost}};

handle_call({set_interval, Interval}, _From, #state{tref=CurrentTRef, job_id=Job_ID}=State) ->
    timer:cancel(CurrentTRef),
    {ok, TRef} = timer:send_interval(Interval, {heartbeat}), 
    format_log(info, "MONITOR_JOB(~p): Job ~p updated the interval to ~p~n", [self(), Job_ID, Interval]), 
    {reply, interval_set, State#state{tref=TRef, interval=Interval}};

handle_call({pause}, _From, #state{tref=TRef, job_id=Job_ID}=State) ->
    timer:cancel(TRef),
    format_log(info, "MONITOR_JOB(~p): Job ~p has been paused~n", [self(), Job_ID]), 
    {reply, paused, State#state{tref=""}};

handle_call({resume}, _From, #state{tref=CurrentTRef, interval=Interval, job_id=Job_ID}=State) ->
    timer:cancel(CurrentTRef),
    {ok, TRef} = timer:send_interval(Interval, {heartbeat}),
    format_log(info, "MONITOR_JOB(~p): Job ~p has been resumed with an interval of ~p~n", [self(), Job_ID, Interval]), 
    {reply, resumed, State#state{tref=TRef}};

handle_call({add_task, Name, Type, Options}, _From, #state{tasks=Tasks, job_id=Job_ID}=State) ->
    Task = #task{type=Type, options=Options},
    format_log(info, "MONITOR_JOB(~p): Job ~p added a new task~n~p~n", [self(), Job_ID, Task]), 
    UpdatedTasks = proplists:delete(Name, Tasks),
    {reply, task_added, State#state{tasks=[{Name, Task}|UpdatedTasks]}};

handle_call({rm_task, Name}, _From, #state{tasks=Tasks, job_id=Job_ID}=State) ->
    NewTasks = proplists:delete(Name, Tasks),
    format_log(info, "MONITOR_JOB(~p): Job ~p removed task ~p~n", [self(), Job_ID, Name]), 
    {reply, task_removed, State#state{tasks=NewTasks}};

handle_call({list_tasks}, _From, #state{tasks=Tasks}=State) ->
    {reply, Tasks, State};

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(stop, State) ->
    {stop, normal, State};

handle_info({'EXIT', _Pid, _Reason}, State) ->
    format_log(error, "MONITOR_JOB(~p): Received EXIT(~p) from ~p...~n", [self(), _Reason, _Pid]),
    {stop, normal, State};

handle_info({heartbeat}, #state{job_id = Job_ID, iteration = Iteration}=State) ->
    format_log(info, "MONITOR_JOB(~p): Job ~p woke up by timer~n", [self(), Job_ID]), 
    spawn_link(fun() -> run_job(State) end),
    {noreply, State#state{iteration = Iteration + 1}};

handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    format_log(info, "MONITOR_JOB(~p): Going down(~p)...~n", [self(), _Reason]),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
create_job_q(AHost) ->
    Q = amqp_util:new_monitor_queue(AHost),

    %% Bind the queue to the targeted exchange
    format_log(info, "MONITOR_JOB(~p): Bind ~p as a targeted queue for job~n", [self(), Q]),
    amqp_util:bind_q_to_targeted(AHost, Q),

    %% Register a consumer to listen to the queue
    format_log(info, "MONITOR_JOB~p): Consume on ~p for job~n", [self(), Q]),
    amqp_util:basic_consume(AHost, Q),

    {ok, Q}.

type_to_routing_key(Type) ->
    case Type of 
        "ping_net_req" -> ?KEY_AGENT_NET_REQ;
        "option_sip_req" -> ?KEY_AGENT_SIP_REQ;
        "basic_call_req" -> ?KEY_AGENT_CALL_REQ;
        _ -> undefined
    end.

run_job(#state{amqp_host = AHost, tasks = Tasks, job_id = Job_ID, iteration = Iteration}) ->
    {ok, Job_Q} = create_job_q(AHost),
    Started = start_tasks(Tasks, AHost, Job_Q, Job_ID, Iteration, []),
    Default = monitor_api:default_headers(Job_Q, <<"logger">>, <<"job_completion">>),
    Headers = lists:append([Default, [{<<"Success">>, <<"true">>}]]),
    Resp = wait_for_tasks(Started, Headers),
    %% Convert Resp to JSON
    %% Send JSON
    amqp_util:queue_delete(AHost, Job_Q),
    format_log(info, "MONITOR_JOB(~p): JOB COMPLETE!!!~nPayload: ~p~n ", [self(), Resp]).

start_tasks([], _AHost, _Job_Q, _Job_ID, _Iteration, Started) ->
    Started;
start_tasks([{Name, Task}|T], AHost, Job_Q, Job_ID, Iteration, Started) ->
    case create_req(Task, Job_Q, Name, Job_ID, Iteration) of
        {ok, JSON} -> 
            format_log(info, "MONITOR_JOB(~p): Job ~p started task ~p~n~p~n", [self(), Job_ID, Name, Task]),
            send_req(AHost, JSON, type_to_routing_key(Task#task.type)),
            start_tasks(T, AHost, Job_Q, Job_ID, Iteration, [{monitor_util:to_binary(Name), Task}|Started]);
        {error, Error} -> 
            format_log(error, "MONITOR_JOB(~p): Create task request error ~p~n ", [self(), Error]),
            start_tasks(T, AHost, Job_Q, Job_ID, Iteration, Started)
    end.

wait_for_tasks([], Resp) ->
    Resp;
wait_for_tasks(Tasks, Resp) ->
    receive
        {_, #amqp_msg{props = Props, payload = Payload}} when Props#'P_basic'.content_type == <<"application/json">> ->
            {struct, Msg} = mochijson2:decode(binary_to_list(Payload)),
            StillPending = proplists:delete(get_value(<<"Task-Name">>, Msg), Tasks),
            TaskReply = [{struct, monitor_api:extract_nondefault(Msg)}],
            TasksReply = lists:append([get_value(<<"Tasks-Reply">>, Resp, []), TaskReply]),
            UpdatedResp = monitor_util:prop_update(<<"Tasks-Reply">>, TasksReply, Resp),
            case get_value(<<"Success">>, Msg) of
                <<"true">> ->
                    wait_for_tasks(StillPending, UpdatedResp);
                _ -> 
                    wait_for_tasks(StillPending, monitor_util:prop_update(<<"Success">>, <<"false">>, UpdatedResp))
            end
    after
        60000 ->
            wait_for_tasks([], monitor_util:prop_update(<<"Success">>, <<"false">>, Resp))
    end.

create_req(Task, Job_Q, Name, Job_ID, Iteration) ->
    Default = monitor_api:default_headers(Job_Q, <<"task">>, monitor_util:to_binary(Task#task.type)),
    Details = monitor_api:optional_default_headers(Job_ID, Name, Iteration),
    Headers = monitor_api:prepare_amqp_prop([Details, Default, Task#task.options]),
    apply(monitor_api, list_to_atom(Task#task.type), [Headers]).

send_req(AHost, JSON, RoutingKey) ->
    format_log(info, "MONITOR_JOB(~p): Sending request to monitor queue on ~p with key ~p~n", [self(), AHost, RoutingKey]),
    amqp_util:monitor_publish(AHost, JSON, <<"application/json">>, RoutingKey).