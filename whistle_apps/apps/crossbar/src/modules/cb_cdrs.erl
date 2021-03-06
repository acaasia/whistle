%%%-------------------------------------------------------------------
%%% @author Edouard Swiac <edouard@2600hz.org>
%%% @copyright (C) 2011, VoIP INC
%%% @doc
%%%
%%% CDR
%%% Read only access to CDR docs
%%%
%%% @end
%%% Created : 30 Jun 2011 Edouard Swiac <edouard@2600hz.org>
%%%-------------------------------------------------------------------
-module(cb_cdrs).

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-include("../../include/crossbar.hrl").
-include_lib("webmachine/include/webmachine.hrl").

-define(SERVER, ?MODULE).
-define(CB_LIST_BY_USER, <<"cdrs/listing_by_user">>).
-define(CB_LIST, <<"cdrs/crossbar_listing">>).

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
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

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
init(_) ->
    {ok, ok, 0}.

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
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

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
handle_info({binding_fired, Pid, <<"v1_resource.allowed_methods.cdrs">>, Payload}, State) ->
    spawn(fun() ->
		  {Result, Payload1} = allowed_methods(Payload),
                  Pid ! {binding_result, Result, Payload1}
	  end),
    {noreply, State};

handle_info({binding_fired, Pid, <<"v1_resource.resource_exists.cdrs">>, Payload}, State) ->
    spawn(fun() ->
		  {Result, Payload1} = resource_exists(Payload),
                  Pid ! {binding_result, Result, Payload1}
	  end),
    {noreply, State};

handle_info({binding_fired, Pid, <<"v1_resource.validate.cdrs">>, [RD, Context | Params]}, State) ->
    spawn(fun() ->
                  crossbar_util:put_reqid(Context),
		  _BPid = crossbar_util:binding_heartbeat(Pid),
		  Context1 = validate(Params, RD, Context),
		  Pid ! {binding_result, true, [RD, Context1, Params]}
	  end),
    {noreply, State};

handle_info({binding_fired, Pid, <<"v1_resource.execute.get.cdrs">>, [RD, Context | Params]}, State) ->
    Pid ! {binding_result, true, [RD, Context, Params]},
    {noreply, State};

handle_info({binding_fired, Pid, _B, Payload}, State) ->
    Pid ! {binding_result, false, Payload},
    {noreply, State};

handle_info(timeout, State) ->
    bind_to_crossbar(),
    {noreply, State};

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
%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function binds this server to the crossbar bindings server,
%% for the keys we need to consume.
%% @end
%%--------------------------------------------------------------------
-spec(bind_to_crossbar/0 :: () ->  no_return()).
bind_to_crossbar() ->
    _ = crossbar_bindings:bind(<<"v1_resource.allowed_methods.cdrs">>),
    _ = crossbar_bindings:bind(<<"v1_resource.resource_exists.cdrs">>),
    _ = crossbar_bindings:bind(<<"v1_resource.validate.cdrs">>),
    crossbar_bindings:bind(<<"v1_resource.execute.get.cdrs">>).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function determines the verbs that are appropriate for the
%% given Nouns.  IE: '/cdr/' can only accept GET
%%
%% Failure here returns 405
%% @end
%%--------------------------------------------------------------------
-spec(allowed_methods/1 :: (Paths :: list()) -> tuple(boolean(), http_methods())).
allowed_methods([]) ->
    {true, ['GET']};
allowed_methods([_]) ->
    {true, ['GET']};
allowed_methods(_) ->
    {false, []}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function determines if the provided list of Nouns are valid.
%%
%% Failure here returns 404
%% @end
%%--------------------------------------------------------------------
-spec(resource_exists/1 :: (Paths :: list()) -> tuple(boolean(), [])).
resource_exists([]) ->
    {true, []};
resource_exists([_]) ->
    {true, []};
resource_exists(_) ->
    {false, []}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function determines if the parameters and content are correct
%% for this request
%%
%% Failure here returns 400
%% @end
%%--------------------------------------------------------------------
-spec validate/3 :: ([binary(),...] | [], #wm_reqdata{}, #cb_context{}) -> #cb_context{}.
validate([], _RD, #cb_context{req_json=RJ, req_verb = <<"get">>}=Context) ->
    try
        load_cdr_summary(Context, RJ)
    catch
        _T:_R ->
	    ST = erlang:get_stacktrace(),
	    ?LOG("Loading summary crashed: ~p: ~p", [_T, _R]),
	    [?LOG("~p", [S]) || S <- ST],
            crossbar_util:response_db_fatal(Context)
    end;
validate([CDRId], _, #cb_context{req_verb = <<"get">>}=Context) ->
    try
        load_cdr(CDRId, Context)
    catch
        _T:_R ->
	    ?LOG("Loading cdr crashed: ~p: ~p", [_T, _R]),
            crossbar_util:response_db_fatal(Context)
    end;
validate(_, _, Context) ->
    crossbar_util:response_faulty_request(Context).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Attempt to load list of CDR, each summarized.
%% @end
%%--------------------------------------------------------------------
-spec load_cdr_summary/2 :: (#cb_context{}, json_object()) -> #cb_context{}.
load_cdr_summary(#cb_context{req_nouns=Nouns, db_name=DbName}=Context, QueryParams) ->
    case Nouns of
	[_, {<<"accounts">>, _AID} | _] ->
	    ?LOG("Loading cdrs for account(s): ~p", [_AID]),
	    Result = crossbar_filter:filter_on_query_string(DbName, ?CB_LIST, wh_json:to_proplist(QueryParams), []),
	    Context#cb_context{resp_data=Result, resp_status=success, resp_etag=automatic};
	[_, {<<"users">>, [UserId] } | _] ->
	    {ok, SipCredsFromDevices} = couch_mgr:get_results(DbName, <<"devices/listing_by_owner">>, [{<<"key">>, UserId}, {<<"include_docs">>, true}]),
	    SipCredsKeys = lists:foldl(fun(SipCred, Acc) ->
					       [[wh_json:get_value([<<"doc">>, <<"sip">>, <<"realm">>], SipCred),
						wh_json:get_value([<<"doc">>, <<"sip">>, <<"username">>], SipCred)]|Acc]
				       end, [], SipCredsFromDevices),
	    Result = crossbar_filter:filter_on_query_string(DbName, ?CB_LIST_BY_USER, wh_json:to_proplist(QueryParams), [{<<"keys">>, SipCredsKeys}]),
	    Context#cb_context{resp_data=Result, resp_status=success, resp_etag=automatic};
	_ ->
	    crossbar_util:response_faulty_request(Context)
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Load a CDR document from the database
%% @end
%%--------------------------------------------------------------------
-spec load_cdr/2 :: (ne_binary(), #cb_context{}) -> #cb_context{}.
load_cdr(CdrId, Context) ->
    crossbar_doc:load(CdrId, Context).
