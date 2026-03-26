module Idunn.Platform
  ( sayHello,
  )
where

import Idunn.Platform.FFI

sayHello :: IO ()
sayHello = idunn_platform_say_hello
