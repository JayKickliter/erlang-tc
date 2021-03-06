-module(dist_secret_society).

-include_lib("eunit/include/eunit.hrl").

-behaviour(gen_server).

-define(SERVER, ?MODULE).

%% API
-export([
    start_link/2,
    stop/0,
    new_actor/3,
    actors/0,
    pk_set/0,
    publish_public_key/0,
    get_actor/1,

    %% Actor API
    id/1,
    sk_share/1,
    pk_share/1,
    msg_inbox/1,
    send_msg/2,

    %% DecryptionMeeting API
    start_decryption_meeting/0,
    accept_decryption_share/1,
    decrypt_msg/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-record(state, {
    actors :: [actor()],
    pk_set :: erlang_tc_pk_set:pk_set(),
    decryption_meeting :: undefined | decryption_meeting()
}).

-record(actor, {
    id :: non_neg_integer(),
    sk_share :: erlang_tc_sk_share:sk_share(),
    pk_share :: erlang_tc_pk_share:pk_share(),
    msg_inbox = undefined :: undefined | erlang_tc_ciphertext:ciphertext()
}).

-record(decryption_meeting, {
    pk_set :: erlang_tc_pk_set:pk_set(),
    ciphertext = undefined :: undefined | erlang_tc_ciphertext:ciphertext(),
    dec_shares = #{} :: #{non_neg_integer() => erlang_tc_dec_share:dec_share()}
}).

-type actor() :: #actor{}.
-type decryption_meeting() :: #decryption_meeting{}.

%%%===================================================================
%%% API
%%%===================================================================

start_link(NumActors, Threshold) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [NumActors, Threshold], []).

stop() ->
    gen_server:call(?SERVER, stop).

actors() ->
    gen_server:call(?SERVER, actors).

get_actor(ID) ->
    gen_server:call(?SERVER, {get_actor, ID}).

pk_set() ->
    gen_server:call(?SERVER, pk_set).

publish_public_key() ->
    gen_server:call(?SERVER, publish_public_key).

start_decryption_meeting() ->
    gen_server:call(?SERVER, start_decryption_meeting).

accept_decryption_share(Actor) ->
    gen_server:call(?SERVER, {accept_decryption_share, Actor}).

decrypt_msg() ->
    gen_server:call(?SERVER, decrypt_msg).

send_msg(Actor, Cipher) ->
    gen_server:call(?SERVER, {send_msg, Actor, Cipher}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([NumNodes, Threshold]) ->
    {ok, new_secret_society(NumNodes, Threshold)}.

handle_call({send_msg, Actor, Cipher}, _From, State) ->
    NewState = send_msg(State, Actor, Cipher),
    {reply, ok, NewState};
handle_call(decrypt_msg, _From, State) ->
    Reply = decrypt_msg(decryption_meeting(State)),
    {reply, Reply, State};
handle_call({accept_decryption_share, Actor}, _From, State) ->
    NewDecryptionMeeting = accept_decryption_share(State, Actor),
    {reply, ok, State#state{decryption_meeting=NewDecryptionMeeting}};
handle_call(start_decryption_meeting, _From, State) ->
    NewState = start_decryption_meeting(State),
    {reply, ok, NewState};
handle_call(publish_public_key, _From, State) ->
    {reply, publish_public_key(State), State};
handle_call({get_actor, ID}, _From, State) ->
    {reply, get_actor(State, ID), State};
handle_call(actors, _From, State) ->
    {reply, actors(State), State};
handle_call(pk_set, _From, State) ->
    {reply, pk_set(State), State};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
handle_call(_Request, _From, State) ->
    lager:warning("unexpected call ~p from ~p", [_Request, _From]),
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Msg, State) ->
    lager:warning("unexpected cast ~p", [_Msg]),
    {noreply, State}.

handle_info(_Info, State) ->
    lager:warning("unexpected message ~p", [_Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

decryption_meeting(State) ->
    State#state.decryption_meeting.

new_secret_society(NumActors, Threshold) ->
    SKSet = erlang_tc_sk_set:random(Threshold),
    PKSet = erlang_tc_sk_set:public_keys(SKSet),

    Actors = lists:map(
        fun(ID) ->
            SKShare = erlang_tc_sk_set:secret_key_share(SKSet, ID),
            PKShare = erlang_tc_pk_set:public_key_share(PKSet, ID),
            new_actor(ID, SKShare, PKShare)
        end,
        lists:seq(1, NumActors)
    ),
    #state{actors = Actors, pk_set = PKSet}.


new_actor(ID, SecretKeyShare, PublicKeyShare) ->
    #actor{id = ID, sk_share = SecretKeyShare, pk_share = PublicKeyShare}.


id(Actor) ->
    Actor#actor.id.

sk_share(Actor) ->
    Actor#actor.sk_share.

pk_share(Actor) ->
    Actor#actor.pk_share.

msg_inbox(Actor) ->
    Actor#actor.msg_inbox.

send_msg(State, {_Name, Actor}, Cipher) ->
    ActorID = id(Actor),
    {ok, OldActor} = get_actor(State, ActorID),
    NewActor = OldActor#actor{msg_inbox=Cipher},
    Actors = actors(State),
    NewActors = setnth(ActorID, Actors, NewActor),
    State#state{actors=NewActors}.

start_decryption_meeting(State) ->
    State#state{decryption_meeting=new_decryption_meeting(pk_set(State))}.

new_decryption_meeting(PKSet) ->
    #decryption_meeting{pk_set=PKSet}.

meeting_cipher(DecryptionMeeting) ->
    DecryptionMeeting#decryption_meeting.ciphertext.

meeting_cipher(DecryptionMeeting, Cipher) ->
    DecryptionMeeting#decryption_meeting{ciphertext=Cipher}.

meeting_pk_set(DecryptionMeeting) ->
    DecryptionMeeting#decryption_meeting.pk_set.

dec_shares(DecryptionMeeting) ->
    DecryptionMeeting#decryption_meeting.dec_shares.

add_share(DecryptionMeeting, ActorID, DecShare) ->
    DecShares = dec_shares(DecryptionMeeting),
    DecryptionMeeting#decryption_meeting{dec_shares=maps:put(ActorID, DecShare, DecShares)}.

accept_decryption_share(State, InputActor) ->
    DecryptionMeeting = decryption_meeting(State),
    {ok, Actor} = get_actor(State, id(InputActor)),
    case msg_inbox(Actor) of
        undefined ->
            DecryptionMeeting;
        Cipher ->
            case meeting_cipher(DecryptionMeeting) of
                undefined ->
                    %% no one in the meeting, accept
                    DecryptionMeeting1 = meeting_cipher(DecryptionMeeting, Cipher),
                    DecShare = erlang_tc_sk_share:decrypt_share(sk_share(Actor), Cipher),
                    ?assert(erlang_tc_pk_share:verify_decryption_share(pk_share(Actor), DecShare, Cipher)),
                    add_share(DecryptionMeeting1, id(Actor), DecShare);
                MeetingCipher ->
                    case erlang_tc_ciphertext:cmp(Cipher, MeetingCipher) of
                        false ->
                            DecryptionMeeting;
                        true ->
                            DecryptionMeeting1 = meeting_cipher(DecryptionMeeting, Cipher),
                            DecShare = erlang_tc_sk_share:decrypt_share(sk_share(Actor), Cipher),
                            ?assert(erlang_tc_pk_share:verify_decryption_share(pk_share(Actor), DecShare, Cipher)),
                            add_share(DecryptionMeeting1, id(Actor), DecShare)
                    end
            end
    end.

decrypt_msg(DecryptionMeeting) ->
    case meeting_cipher(DecryptionMeeting) of
        undefined ->
            {error, cannot_decrypt};
        Cipher ->
            PKSet = meeting_pk_set(DecryptionMeeting),
            erlang_tc_pk_set:decrypt(PKSet, maps:to_list(dec_shares(DecryptionMeeting)), Cipher)
    end.

actors(State) ->
    State#state.actors.

pk_set(State) ->
    State#state.pk_set.

publish_public_key(State) ->
    erlang_tc_pk_set:public_key(pk_set(State)).

get_actor(State, ID) ->
    try
        Actor = lists:nth(ID, actors(State)),
        {ok, Actor}
    catch
        _W:_Why:_ST ->
            {error, not_found}
    end.

setnth(1, [_ | Rest], New) -> [New | Rest];
setnth(I, [E | Rest], New) -> [E | setnth(I - 1, Rest, New)].
