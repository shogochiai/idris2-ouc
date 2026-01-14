export const idlFactory = ({ IDL }) => {
  return IDL.Service({
    'test_c_wrapper' : IDL.Func([], [IDL.Nat], ['query']),
    'test_direct' : IDL.Func([], [IDL.Nat], ['query']),
    'test_ffi' : IDL.Func([], [IDL.Nat], ['query']),
  });
};
export const init = ({ IDL }) => { return []; };
