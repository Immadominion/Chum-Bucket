/// Two REAL mainnet transaction shapes for a gasless USDC -> SOL swap, as
/// Jupiter's Swap API returns them for signing — the same bytes as the API
/// repo's `tests/fixtures/jupiterGasless.ts`. Read from public mainnet
/// transactions on 2 October 2026 with every signature zeroed and the
/// swapper replaced by the BIP-39 test phrase's wallet ([kTestPhrase] at
/// m/44'/501'/0'/0'): public test data, never a real wallet. Everything else
/// (instructions, data, programs, Jupiter's gas wallet, the market maker,
/// lookup tables) is the original. Sources and rules:
/// docs/gasless-sol-topup.md in the API repo.
library;

const kSwapOwner = 'HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk';
const kSwapOwnerUsdc = '5N3f1tj9v1vc5TUZ8S7mCAnVmjVKrfnzXWhxLaxyZAgt';
const kSwapOwnerWsol = 'CJoNbVgQcSsTHuTza6CSYoSuojo2vDMN3mxzM1GcTPSF';

/// Metis route_v2, Jupiter-sponsored (fee payer gasTzr…), 12.540807 USDC in.
/// The original swapper received 106,119,149 lamports.
const kMetisSwapBase64 =
    'AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAgAIABQoKI/LW57XKxPlrnBnjR8pwJqlB8IMXoWShoopB'
    'Sd7LSPA2J2JGp1ud4zSe1CsV4jL2UY/CD1/NTx1k6B+b0lj3iODf8VvwBTKUkIJ/Y9Eif0dq'
    'phZhHVI9k4/9JFpM34On/90BBnpik/KR8QwNjg/a6SNBG1AeiRuWANppcU+NcEDS8nxGHynp'
    '/roauKzTlJapxlsK5ipxPwH5QamTv1XtAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AACMlyWPTiSJ8bs9ECkUjg2DC1oTmdr/EIQEjnvY2+n4WQMGRm/lIRcy/+ytunLDm+e8jOW7'
    'xfcSayxDmzpAAAAABHnVW/IxwG7udMVuzmgVB/2xst6j9I5RArHNola8E48G3fbh12Whk9nL'
    '4UbO63msHLSF7V9bN5E6jPWFfv8AqRXMJl/vSiTLZMuHVKmXVpRLEuUTtd8T4WH3IKgpkT0S'
    'BgcABQJ3jQEABwAJA/+eAAAAAAAABgYAAwEQBQkBAQgYAQQDDhAJCQgNCAIRAQsMCgMECQkT'
    'EggPKLtk+swxxK8Uh1u/AAAAAAA/ilMGAAAAACIACwAAAAEAAACNABAnAAEJAwMBAQEJBQIB'
    'AAwCAAAAOLYWAAAAAAACKb+VBypPvwTfcXWT5zi8zCEnKBXCRxqA2fn1VbDUhCUABAAoARdq'
    'qcPrNb0kOj4f4oBo3tqeUfk5BcRkq+duwyJjby342QOAhYQDgod/';
const kMetisBlockTime = 1790979540;
const kMetisInAmount = 12540807;

/// quoted_out 106,138,175 less the route's 11 bps fee.
const kMetisOutAmount = 106021423;
const kMetisFeeBps = 11;

/// JupiterZ fill paid by the market maker, 0.543057 USDC in. The original
/// swapper received 4,592,968 lamports.
const kRfqSwapBase64 =
    'AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAgAIABg1l4eWU9W+LbzHkYy5erq32+K0Kp0kwgKUELcMB'
    'r/mwIfA2J2JGp1ud4zSe1CsV4jL2UY/CD1/NTx1k6B+b0lj3CaG3UKbDgJznjNXjNbmUyiwU'
    'Z6yLBqOxiJwnz/wBDQhwMIoK5lD0f8OUQD7+I20js7jTCATSPJ/yV+rcGGj34Ijg3/Fb8AUy'
    'lJCCf2PRIn9HaqYWYR1SPZOP/SRaTN+DmSb6l/rN0Xfh+NsexPDFly2ez3JXxMpRSb8q/WeK'
    'C71A0vJ8Rh8p6f66Gris05SWqcZbCuYqcT8B+UGpk79V7QAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAwZGb+UhFzL/7K26csOb57yM5bvF9xJrLEObOkAAAAAGm4hX/quBhPto'
    'f2NGGMA12sQ53BrrO1WYoPAAAAAAAQbd9uHXZaGT2cvhRs7reawctIXtX1s3kTqM9YV+/wCp'
    'SlhJ+3Kju+kf3FsOalf2PFoctFsgZ6btDKzTY5XIoQLG+nrzvtutOj1l82qryXQxsbvkwtL2'
    '4OR8pgIDRS9dYV8P00lGm9SyVMA045BoMbKugYy4cY4lwQ/FUwuVvGAwBQgACQMVDQAAAAAA'
    'AAgABQLtYQAACwwBAAYDCwUMCgkKBwIlqGC3o1wKKKBRSQgAAAAAAD0nRgAAAAAAHi/AagAA'
    'AAAAAAIKAAcCAQQMAgAAAPURAAAAAAAACgEEAREA';
const kRfqBlockTime = 1790979820;
const kRfqInAmount = 543057;
const kRfqOutAmount = 4592968;
const kRfqFeeBps = 10;
const kRfqMaker = '7rhxnLV8C77o6d8oz26AgK8x8m5ePsdeRawjqvojbjnQ';
