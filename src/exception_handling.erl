%% Copyright (c) 2009 Jacob Vorreuter <jacob.vorreuter@gmail.com>
%% 
%% Permission is hereby granted, free of charge, to any person
%% obtaining a copy of this software and associated documentation
%% files (the "Software"), to deal in the Software without
%% restriction, including without limitation the rights to use,
%% copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the
%% Software is furnished to do so, subject to the following
%% conditions:
%% 
%% The above copyright notice and this permission notice shall be
%% included in all copies or substantial portions of the Software.
%% 
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
%% OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
%% NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
%% HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
%% WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
%% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
%% OTHER DEALINGS IN THE SOFTWARE.
%%
%%
%% Traverse the list of forms and accumulate a list of record 
%% definitions.  Once the end of the attributes section has been 
%% reached, insert the expanded_record_fields/1 function which 
%% takes a record name as an argument and returns a list of field 
%% names.
%%

-module(exception_handling).
-behaviour(gen_server).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, 
		 handle_info/2, terminate/2, code_change/3]).

-export([parse_transform/2, register/2, handle/1]).

parse_transform(Forms, _Options) ->
	replace_catch(Forms).

replace_catch(Terms) when is_list(Terms) ->
	[replace_catch(Term) || Term <- Terms];
	
replace_catch({'catch',L,Term}) ->
	{call,L,{remote,L,{atom,L,?MODULE},{atom,L,handle}},[{'catch',L,replace_catch(Term)}]};

replace_catch(Terms) when is_tuple(Terms) ->
	list_to_tuple([replace_catch(Term) || Term <- tuple_to_list(Terms)]);
	
replace_catch(Term) -> Term.

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
	
register(Err, Callback) ->
	gen_server:cast(?MODULE, {register, Err, Callback}).
	
handle({'EXIT', Err}) ->
	spawn(registered_exception_handlers, handle, [Err]),
	{'EXIT', Err};
	
handle(Other) -> Other.

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([]) ->
	{ok, gb_trees:empty()}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call(_, _From, State) -> {reply, {error, invalid_call}, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast({register, Err, Callback}, Tree) ->
	Tree1 = gb_trees:enter(Err, Callback, Tree),
	Src = source(gb_trees:to_list(Tree1)),
	dynamic_compile:load_from_string(Src),
	{noreply, Tree1};

handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

source(RegisteredExceptions) ->
"
-module(registered_exception_handlers).
-export([handle/1]).
" ++ lists:flatten(["
handle(" ++ lists:flatten(format_error_string(Err0)) ++ " = Error) ->
	" ++ lists:flatten(io_lib:format("~p:~p(Error);", [Module, Fun]))
|| {Err0, {Module, Fun}} <- RegisteredExceptions]) ++ "

handle(_) -> ok.

".

format_error_string(Terms) when is_list(Terms) ->
	"[" ++ string:join([format_error_string(Term) || Term <- Terms], ", ") ++ "]";
	
format_error_string(Terms) when is_tuple(Terms) ->
	"{" ++ string:join([format_error_string(Term) || Term <- tuple_to_list(Terms)], ", ") ++ "}";
	
format_error_string('_') -> "_";

format_error_string(Term) -> io_lib:format("~p", [Term]).