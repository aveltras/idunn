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
-- {-# LANGUAGE AllowAmbiguousTypes #-}
-- {-# LANGUAGE DataKinds #-}
-- {-# LANGUAGE FunctionalDependencies #-}
-- {-# LANGUAGE GADTs #-}
-- {-# LANGUAGE PolyKinds #-}
-- {-# LANGUAGE ScopedTypeVariables #-}
-- {-# LANGUAGE TypeApplications #-}
-- {-# LANGUAGE TypeFamilies #-}
-- {-# LANGUAGE UndecidableInstances #-}
-- {-# LANGUAGE UndecidableSuperClasses #-}

module Idunn.Core where

--   ( SystemRegistry (..),
--     IsSystemRegistry (..),
--     emptySystemRegistry,
--     ResourceRegistry (..),
--     Resource (..),
--     initializeAllResources,
--     getResource,
--     System (..),
--     Idunn,
--     initializeAllSystems,
--     runAllSystems,
--     getSystem,
--   )
-- where

-- import Control.Monad.Reader
-- import Data.Kind
-- import Idunn.TypeLevel
-- import UnliftIO (MonadIO, Typeable, liftIO)
-- import UnliftIO.Resource (MonadResource)

-- newtype SystemRegistry systems = SystemRegistry (HList systems)

-- data IsSystemRegistry resources = forall systems. (RunSystems resources systems systems) => IsSystemRegistry (SystemRegistry systems)

-- emptySystemRegistry :: IsSystemRegistry resources
-- emptySystemRegistry = IsSystemRegistry $ SystemRegistry HNil

-- newtype ResourceRegistry resources = ResourceRegistry (HList resources)

-- type Idunn resources systems =
--   ( InitializeSystems (Nub (ExpandResources (CollectResources systems))) systems '[],
--     InitializeResources (Nub (ExpandResources (CollectResources systems))) '[],
--     RunSystems resources systems systems,
--     Nub (ExpandResources (CollectResources systems)) ~ resources,
--     All System systems
--   )

-- class
--   ( All System (Dependencies system),
--     All Resource (Resources system),
--     Typeable system
--   ) =>
--   System system
--   where
--   type Resources system :: [Type]
--   type Resources system = '[]

--   type Dependencies system :: [Type]
--   type Dependencies system = '[]

--   initializeSystem ::
--     forall (resources :: [Type]) (initialized :: [Type]) env m.
--     ( IsSubset (Dependencies system) initialized,
--       IsSubset (Resources system) resources,
--       MonadResource m,
--       MonadReader env m,
--       HasSystems env initialized,
--       HasResources env resources
--     ) =>
--     m system

--   runSystem :: forall systems m env. (MonadIO m, MonadReader env m, HasSystems env systems) => m ()

-- initializeAllSystems ::
--   forall (systems :: [Type]) resources m.
--   ( MonadResource m,
--     resources ~ Nub (ExpandResources (CollectResources systems)),
--     InitializeSystems resources systems '[]
--   ) =>
--   ResourceRegistry resources -> m (SystemRegistry systems)
-- initializeAllSystems resources = do
--   SystemRegistry <$> initializeSystems @resources @systems @'[] resources HNil

-- class (All System remaining) => InitializeSystems (resources :: [Type]) (remaining :: [Type]) (initialized :: [Type]) where
--   initializeSystems :: (MonadResource m, MonadIO m) => ResourceRegistry resources -> HList initialized -> m (HList remaining)

-- instance InitializeSystems all '[] initialized where
--   initializeSystems _ _ = pure HNil

-- instance
--   ( System system,
--     IsSubset (Dependencies system) initialized,
--     IsSubset (Resources system) resources,
--     InitializeSystems resources systems (system ': initialized)
--   ) =>
--   InitializeSystems resources (system ': systems) initialized
--   where
--   initializeSystems resources currentRegistry = do
--     liftIO $ putStrLn "initializeSystems"
--     let env = (resources, SystemRegistry @initialized currentRegistry)
--     system <- runReaderT (initializeSystem @system @resources @initialized) env
--     next <- initializeSystems @resources @systems @(system ': initialized) resources $ HCons system currentRegistry
--     pure $ HCons system next

-- class HasSystems env systems | env -> systems where
--   getSystems :: env -> SystemRegistry systems

-- instance HasSystems (ResourceRegistry allSystems, SystemRegistry systems) systems where
--   getSystems = snd

-- getSystem ::
--   forall system systems env m.
--   ( MonadReader env m,
--     HasSystems env systems,
--     Member system systems
--   ) =>
--   m system
-- getSystem = do
--   SystemRegistry registry <- asks (getSystems @env)
--   pure $ getH @system registry

-- class (All Resource (DependsOn resource), Typeable resource) => Resource resource where
--   type DependsOn resource :: [Type]
--   type DependsOn resource = '[]
--   initializeResource :: (MonadResource m, MonadReader env m, HasResources env resources, IsSubset (DependsOn resource) resources) => m resource

-- type family CollectResources (systems :: [Type]) :: [Type] where
--   CollectResources '[] = '[]
--   CollectResources (x ': xs) = Append (Resources x) (CollectResources xs)

-- type family ExpandResources (rs :: [Type]) :: [Type] where
--   ExpandResources '[] = '[]
--   ExpandResources (r ': rs) = Append (ExpandResources (DependsOn r)) (r ': ExpandResources rs)

-- initializeAllResources ::
--   forall systems resources m.
--   ( MonadResource m,
--     resources ~ Nub (ExpandResources (CollectResources systems)),
--     InitializeResources resources '[]
--   ) =>
--   m (ResourceRegistry resources)
-- initializeAllResources = ResourceRegistry <$> initializeResources @(Nub (ExpandResources (CollectResources systems))) @'[] HNil

-- class InitializeResources (remaining :: [Type]) (initialized :: [Type]) where
--   initializeResources :: (MonadResource m) => HList initialized -> m (HList remaining)

-- instance InitializeResources '[] initialized where
--   initializeResources _ = pure HNil

-- instance
--   ( Resource resource,
--     IsSubset (DependsOn resource) initialized,
--     InitializeResources remaining (resource ': initialized)
--   ) =>
--   InitializeResources (resource ': remaining) initialized
--   where
--   initializeResources currentRegistry = do
--     res <- runReaderT (initializeResource @resource) $ ResourceRegistry currentRegistry
--     next <- initializeResources @remaining @(resource ': initialized) $ HCons res currentRegistry
--     pure $ HCons res next

-- class HasResources env resources | env -> resources where
--   getResources :: env -> ResourceRegistry resources

-- instance HasResources (ResourceRegistry resources) resources where
--   getResources = id

-- instance HasResources (ResourceRegistry resources, SystemRegistry systems) resources where
--   getResources = fst

-- getResource ::
--   forall resource resources env m.
--   ( MonadReader env m,
--     HasResources env resources,
--     Member resource resources
--   ) =>
--   m resource
-- getResource = do
--   ResourceRegistry registry <- asks (getResources @env)
--   pure $ getH @resource registry

-- runAllSystems :: forall resources m. (MonadIO m) => ResourceRegistry resources -> IsSystemRegistry resources -> m ()
-- runAllSystems resources (IsSystemRegistry (registry :: SystemRegistry systems)) = runSystems @resources @systems @systems resources registry

-- class RunSystems (resources :: [Type]) (remaining :: [Type]) (all :: [Type]) where
--   runSystems :: (MonadIO m) => ResourceRegistry resources -> SystemRegistry all -> m ()

-- instance RunSystems resources '[] all where
--   runSystems _ _ = pure ()

-- instance (System system, RunSystems resources systems all, Member system all) => RunSystems resources (system ': systems) all where
--   runSystems resources registry = do
--     -- On exécute le système actuel en lui fournissant le registre complet pour ses getSystem
--     -- On utilise runReaderT pour satisfaire la contrainte MonadReader de runSystem
--     runReaderT (runSystem @system @all) (resources, registry)

--     -- On passe à la suite
--     runSystems @resources @systems @all resources registry

-- -- class RunSystems (remaining :: [Type]) (all :: [Type]) where
-- --   runSystems :: forall m env. (MonadIO m, MonadReader env m, HasSystems env all) => m ()

-- -- instance RunSystems '[] all where
-- --   runSystems = pure ()

-- -- instance (System system, RunSystems systems all) => RunSystems (system ': systems) all where
-- --   runSystems = do
-- --     runSystem @system @all
-- --     runSystems @systems @all
