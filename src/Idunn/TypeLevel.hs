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
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Idunn.TypeLevel where

import Data.Kind (Constraint, Type)
import GHC.TypeLits

type family All (c :: k -> Constraint) (ts :: [k]) :: Constraint where
  All c '[] = ()
  All c (x ': xs) = (c x, All c xs)

type family IsIn (x :: Type) (xs :: [Type]) :: Constraint where
  IsIn x (x ': xs) = ()
  IsIn x (y ': xs) = IsIn x xs
  IsIn x '[] = TypeError ('Text "Missing element: " ':<>: 'ShowType x)

type family IsSubset (subset :: [Type]) (target :: [Type]) :: Constraint where
  IsSubset '[] target = ()
  IsSubset (x ': xs) target = (IsIn x target, Member x target, IsSubset xs target)

type family Contains (x :: Type) (xs :: [Type]) :: Bool where
  Contains x '[] = 'False
  Contains x (x ': xs) = 'True
  Contains x (y ': xs) = Contains x xs

type family Nub (xs :: [Type]) :: [Type] where
  Nub '[] = '[]
  Nub (x ': xs) = If (Contains x xs) (Nub xs) (x ': Nub xs)

type family If (cond :: Bool) (thenPart :: a) (elsePart :: a) :: a where
  If 'True thenPart elsePart = thenPart
  If 'False thenPart elsePart = elsePart

type family Append (xs :: [Type]) (ys :: [Type]) :: [Type] where
  Append '[] ys = ys
  Append (x ': xs) ys = x ': Append xs ys

data HList (ts :: [Type]) where
  HNil :: HList '[]
  HCons :: t -> HList ts -> HList (t ': ts)

class Member (t :: Type) (ts :: [Type]) where
  getH :: HList ts -> t

instance {-# OVERLAPPING #-} Member t (t ': ts) where
  getH (HCons x _) = x

instance (Member t ts) => Member t (any ': ts) where
  getH (HCons _ xs) = getH @t xs
