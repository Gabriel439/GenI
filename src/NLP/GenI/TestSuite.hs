--  GenI surface realiser
--  Copyright (C) 2005-2009 Carlos Areces and Eric Kow
--
--  This program is free software; you can redistribute it and/or
--  modify it under the terms of the GNU General Public License
--  as published by the Free Software Foundation; either version 2
--  of the License, or (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program; if not, write to the Free Software
--  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

module NLP.GenI.TestSuite
where

import qualified Data.Map as Map
import NLP.GenI.Semantics

data TestCase = TestCase
       { tcName :: String
       , tcSemString :: String -- ^ for gui
       , tcSem  :: SemInput
       , tcExpected :: [String] -- ^ expected results (for testing)
       , tcOutputs :: [(String, Map.Map (String,String) [String])]
       -- ^ results we actually got, and their traces (for testing)
       } deriving Show
