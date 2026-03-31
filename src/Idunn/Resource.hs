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

module Idunn.Resource where

import UnliftIO
import UnliftIO.Resource

class HasResources env where
  getResources :: env -> Resources

newtype Resources = Resources
  { unResources :: IORef [ReleaseKey]
  }

initResources :: (MonadIO m) => m Resources
initResources = Resources <$> newIORef mempty

allocateAndStore :: (MonadResource m) => Resources -> IO a -> (a -> IO ()) -> m a
allocateAndStore (Resources ref) up down = do
  (releaseKey, resource) <- allocate up down
  atomicModifyIORef' ref $ \keys -> (releaseKey : keys, ())
  pure resource

cleanupResources :: (MonadResource m) => Resources -> m ()
cleanupResources (Resources ref) = do
  keys <- atomicModifyIORef' ref $ \keys -> ([], keys)
  mapM_ release keys
