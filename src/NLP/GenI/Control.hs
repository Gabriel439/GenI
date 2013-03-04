-- GenI surface realiser
-- Copyright (C) 2013 Eric Kow (Computational Linguistics Ltd)
--
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- as published by the Free Software Foundation; either version 2
-- of the License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

module NLP.GenI.Control where

import           Control.Monad

import           NLP.GenI.Flag
import           NLP.GenI.OptimalityTheory

-- | Inputs that go around a single testcase/input
data Params = Params
    { builderType :: Maybe BuilderType
      -- | Custom morph realiser may define a custom set of flags
      --   that it accepts
    , morphFlags  :: [Flag]
    , geniFlags   :: [Flag]
      -- | OT constraints (optional)
    , ranking     :: Maybe OtRanking
    }


-- | Note that this affects the geniFlags; we assume the morph flags
--   are not our business
instance HasFlags Params where
    flags       = geniFlags
    onFlags f p = p { geniFlags = f (geniFlags p) }

updateParams :: Params -- ^ new
             -> Params -- ^ old
             -> Params
updateParams new old = old
    { builderType = builderType new
    , morphFlags  = updateFlags (morphFlags new) (morphFlags old)
    , geniFlags   = updateFlags (geniFlags  new) (geniFlags  old)
    , ranking     = ranking new `mplus` ranking old
    }
