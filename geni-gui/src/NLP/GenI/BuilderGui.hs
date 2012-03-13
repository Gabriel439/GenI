-- GenI surface realiser
-- Copyright (C) 2005 Carlos Areces and Eric Kow
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

{-# LANGUAGE RankNTypes #-}
module NLP.GenI.BuilderGui
where

import Graphics.UI.WX

import qualified NLP.GenI.Builder as B
import NLP.GenI (ProgStateRef, GeniResult)
import NLP.GenI.Configuration (Params)
import NLP.GenI.Semantics
import NLP.GenI.Statistics (Statistics)

data BuilderGui = BuilderGui
  { resultsPnl  :: forall a . ProgStateRef -> SemInput -> (Window a) -> IO ([GeniResult],Statistics,Layout,Layout)
  , debuggerPnl :: forall a . (Window a) -> Params -> B.Input -> String -> IO Layout }
