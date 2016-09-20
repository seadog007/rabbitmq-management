%%   The contents of this file are subject to the Mozilla Public License
%%   Version 1.1 (the "License"); you may not use this file except in
%%   compliance with the License. You may obtain a copy of the License at
%%   http://www.mozilla.org/MPL/
%%
%%   Software distributed under the License is distributed on an "AS IS"
%%   basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%   License for the specific language governing rights and limitations
%%   under the License.
%%
%%   The Original Code is RabbitMQ Management Plugin.
%%
%%   The Initial Developer of the Original Code is GoPivotal, Inc.
%%   Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.
%%

-module(rabbit_mgmt_wm_channel).

-export([init/3, rest_init/2, to_json/2, content_types_provided/2, is_authorized/2]).
-export([resource_exists/2]).
-export([variances/2]).

-import(rabbit_misc, [pget/2, pset/3]).

-include("rabbit_mgmt.hrl").
-include("rabbit_mgmt_metrics.hrl").
-include_lib("rabbit_common/include/rabbit.hrl").

%%--------------------------------------------------------------------

init(_, _, _) -> {upgrade, protocol, cowboy_rest}.

rest_init(Req, _Config) ->
    {ok, rabbit_mgmt_cors:set_headers(Req, ?MODULE), #context{}}.

variances(Req, Context) ->
    {[<<"accept-encoding">>, <<"origin">>], Req, Context}.

content_types_provided(ReqData, Context) ->
   {[{<<"application/json">>, to_json}], ReqData, Context}.

resource_exists(ReqData, Context) ->
    case channel(ReqData) of
        not_found -> {false, ReqData, Context};
        _Conn     -> {true, ReqData, Context}
    end.

to_json(ReqData, Context) ->
    case channel(ReqData) of
        not_found -> rabbit_mgmt_util:not_found("channel", ReqData, Context);
        Ch -> rabbit_mgmt_util:reply({struct, rabbit_mgmt_format:strip_pids(Ch)},
                                      ReqData, Context)
    end.

is_authorized(ReqData, Context) ->
    try
        rabbit_mgmt_util:is_authorized_user(ReqData, Context, channel(ReqData))
    catch
        {error, invalid_range_parameters, Reason} ->
            rabbit_mgmt_util:bad_request(iolist_to_binary(Reason), ReqData, Context)
    end.

%%--------------------------------------------------------------------

channel(ReqData) ->
    Members = pg2:get_members(management_db),
    PidResults = delegate_call(Members,
                               {get_channel,
                                rabbit_mgmt_util:id(channel, ReqData),
                                rabbit_mgmt_util:range(ReqData)}),
    case [R || {_, [_|_] = R} <- PidResults] of
        [Channel] ->
            Consumers = fetch_consumer_details(Members, Channel),
            rabbit_mgmt_format:clean_consumer_details(
              pset(consumer_details, Consumers, Channel));
        _ -> not_found
    end.

fetch_consumer_details(Members, Channel) ->
    PidConsumers = delegate_call(Members, {get_consumers, [pget(pid, Channel)]}),
    lists:append([Cs || {_, Cs} <- PidConsumers]).

delegate_call(Members, Args) ->
    element(1, delegate:call(Members, ?DELEGATE_PREFIX, Args)).
