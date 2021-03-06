-module(erlang_tc_sk_share).

-export([
    decrypt_share/2,
    sign/2
]).

-type sk_share() :: reference().

-export_type([sk_share/0]).

-spec decrypt_share(
    SKShare :: sk_share(),
    Ciphertext :: erlang_tc_ciphertext:ciphertext()
) -> erlang_tc_dec_share:dec_share().
decrypt_share(SKShare, Ciphertext) ->
    erlang_tc:sk_share_decryption_share(SKShare, Ciphertext).

-spec sign(
    SKShare :: sk_share(),
    Msg :: binary()
) -> erlang_tc_sig_share:sig_share().
sign(SKShare, Msg) ->
    erlang_tc:sk_share_sign(SKShare, Msg).
