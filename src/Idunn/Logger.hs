{-
 Copyright (C) 2026 Romain Viallard

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as
 published by the Free Software Foundation, either version 3 of the
 License, or (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with this program. If not, see <http://www.gnu.org/licenses/>.
-}

module Idunn.Logger
  ( logDebug,
    logInfo,
    logWarning,
    logError,
  )
where

import Foreign.C
import Foreign.C.ConstPtr
import Idunn.Logger.FFI
import UnliftIO

logDebug :: (MonadIO m) => String -> m ()
logDebug msg = liftIO $ withCString msg $ \c'msg -> idunn_log_debug $ ConstPtr c'msg

logInfo :: (MonadIO m) => String -> m ()
logInfo msg = liftIO $ withCString msg $ \c'msg -> idunn_log_info $ ConstPtr c'msg

logWarning :: (MonadIO m) => String -> m ()
logWarning msg = liftIO $ withCString msg $ \c'msg -> idunn_log_warning $ ConstPtr c'msg

logError :: (MonadIO m) => String -> m ()
logError msg = liftIO $ withCString msg $ \c'msg -> idunn_log_error $ ConstPtr c'msg
