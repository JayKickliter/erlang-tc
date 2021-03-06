use crate::atom::{cannot_combine, error, ok};
use crate::bin::Bin;
use crate::ciphertext::CiphertextArc;
use crate::commitment::CommitmentArc;
use crate::dec_share::DecShareArc;
use crate::pk::{PkArc, PkRes};
use crate::pk_share::{PKShareArc, PKShareRes};
use crate::sig::SigRes;
use crate::sig_share::SigShareArc;
use rustler::{Atom, Encoder, Env, NifResult, ResourceArc, Term};
use threshold_crypto::PublicKeySet;

/// Struct to hold PublicKey
pub struct PKSetRes {
    pub pk_set: PublicKeySet,
}

pub type PKSetArc = ResourceArc<PKSetRes>;

pub fn load(env: Env) -> bool {
    rustler::resource!(PKSetRes, env);
    true
}

#[rustler::nif(name = "pk_set_from_commitment")]
fn pk_set_from_commitment(c_arc: CommitmentArc) -> PKSetArc {
    ResourceArc::new(PKSetRes {
        pk_set: PublicKeySet::from(c_arc.commitment.clone()),
    })
}

#[rustler::nif(name = "pk_set_public_key")]
fn pk_set_public_key(pk_set_arc: PKSetArc) -> PkArc {
    ResourceArc::new(PkRes {
        pk: pk_set_arc.pk_set.public_key(),
    })
}

#[rustler::nif(name = "pk_set_threshold")]
fn pk_set_threshold(pk_set_arc: PKSetArc) -> usize {
    pk_set_arc.pk_set.threshold()
}

#[rustler::nif(name = "pk_set_public_key_share")]
fn pk_set_public_key_share(pk_set_arc: PKSetArc, i: i64) -> PKShareArc {
    ResourceArc::new(PKShareRes {
        share: pk_set_arc.pk_set.public_key_share(i),
    })
}

#[rustler::nif(name = "pk_set_decrypt")]
fn pk_set_decrypt(
    pk_set_arc: PKSetArc,
    dec_shares: Vec<(i64, DecShareArc)>,
    cipher_arc: CiphertextArc,
) -> (Atom, Bin) {
    let decrypted: Result<Vec<u8>, threshold_crypto::error::Error> = pk_set_arc.pk_set.decrypt(
        dec_shares.iter().map(|(i, dsa)| (*i, &dsa.dec_share)),
        &cipher_arc.cipher,
    );

    match decrypted {
        Ok(d) => (ok(), Bin(d)),
        _ => (error(), Bin(vec![])),
    }
}

#[rustler::nif(name = "pk_set_combine_signatures")]
fn pk_set_combine_signatures<'a>(
    env: Env<'a>,
    pk_set_arc: PKSetArc,
    sig_shares: Vec<(i64, SigShareArc)>,
) -> NifResult<Term<'a>> {
    let res = pk_set_arc
        .pk_set
        .combine_signatures(sig_shares.iter().map(|(i, sa)| (*i, &sa.sig_share)));

    match res {
        Ok(r) => Ok(ResourceArc::new(SigRes { sig: r }).encode(env)),
        _ => Ok((error(), cannot_combine()).encode(env)),
    }
}
