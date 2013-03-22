%%%=============================================================================
%%% Permission to use, copy, modify, and/or distribute this software for any
%%% purpose with or without fee is hereby granted, provided that the above
%%% copyright notice and this permission notice appear in all copies.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
%%%
%%% @doc
%%% A server keeping track of event handler registration. It will attach/detach
%%% the {@link syslog_h} event handler to the `error_logger' as necessary (e.g.
%%% if the handler gets detached accidentially on error) providing it with the
%%% needed UDP socket.
%%% @end
%%%=============================================================================
-module(syslog_monitor).

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
         handle_cast/2,
         handle_call/3,
         handle_info/2,
         code_change/3,
         terminate/2]).

-include("syslog.hrl").

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% Starts the locally registered monitor server which in turn will attach the
%% {@link syslog_h} event handler at the `error_logger' event manager.
%% @end
%%------------------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() -> gen_server:start_link(?MODULE, [], []).

%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

-record(state, {socket :: gen_udp:socket()}).

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
init([]) ->
    process_flag(trap_exit, true),
    {ok, Socket} = gen_udp:open(0, [binary, {reuseaddr, true}]),
    case syslog_h:attach(Socket) of
        ok ->
            {ok, #state{socket = Socket}};
        Error ->
            ok = gen_udp:close(Socket),
            {stop, Error}
    end.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
handle_call(_Request, _From, State) -> {reply, undef, State}.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
handle_cast(_Request, State) -> {noreply, State}.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
handle_info({gen_event_EXIT, syslog_h, shutdown}, State) ->
    {stop, normal, State}; %% error_logger was shutdown properly
handle_info({gen_event_EXIT, syslog_h, _}, State) ->
    ok = syslog_h:attach(State#state.socket), %% try to re-add the event handler
    {noreply, State};
handle_info({udp_closed, Socket}, State = #state{socket = Socket}) ->
    {stop, udp_closed, State#state{socket = undefined}}; %% get restarted
handle_info(_Info, State) ->
    {noreply, State}.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) -> State.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
terminate(_Reason, #state{socket = undefined}) ->
    syslog_h:detach(),
    ok;
terminate(_Reason, #state{socket = Socket}) ->
    syslog_h:detach(),
    gen_udp:close(Socket).