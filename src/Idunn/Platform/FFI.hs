{-# LANGUAGE CApiFFI #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UnboxedTuples #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -ddump-splices #-}

module Idunn.Platform.FFI where

import HsBindgen.TH

let cfg :: Config
    cfg = def {clang = def {argsInner = ["-std=c23"]}}
    cfgTH :: ConfigTH
    cfgTH = def {categoryChoice = useUnsafeCategory}
 in withHsBindgen cfg cfgTH $ do
      hashInclude "idunn/platform.h"
