-- ----------------------------------------------------------------------
-- GenI surface realiser
-- Copyright (C) 2009 Eric Kow
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
-- ----------------------------------------------------------------------

module NLP.GenI.Test where

import Control.Applicative
import Data.List ( isPrefixOf )
import System.Environment ( getArgs )

import Test.Framework

import NLP.GenI.Test.FeatureStructure ( suite )
import NLP.GenI.Test.Parser ( suite )
import NLP.GenI.Test.GeniVal ( suite )
import NLP.GenI.Test.LexicalSelection ( suite )
import NLP.GenI.Test.Lexicon ( suite )
import NLP.GenI.Test.Morphology ( suite )
import NLP.GenI.Test.Polarity ( suite )
import NLP.GenI.Test.Semantics ( suite )
import NLP.GenI.Test.Simple.SimpleBuilder ( suite )
import NLP.GenI.Regression

runTests :: IO ()
runTests = do
    args <- filter (not . (`isPrefixOf` "--unit-tests")) `fmap` getArgs
    funcSuite <- NLP.GenI.Regression.mkSuite
    opts_ <- interpretArgsOrExit args
    let opts = opts_
            { ropt_test_options = setMaxTests 25 <$> ropt_test_options opts_ }
    flip defaultMainWithArgs args
        [ NLP.GenI.Test.GeniVal.suite
        , NLP.GenI.Test.Parser.suite
        , NLP.GenI.Test.FeatureStructure.suite
        , NLP.GenI.Test.LexicalSelection.suite
        , NLP.GenI.Test.Lexicon.suite
        , NLP.GenI.Test.Morphology.suite
        , NLP.GenI.Test.Polarity.suite
        , NLP.GenI.Test.Semantics.suite
        , NLP.GenI.Test.Simple.SimpleBuilder.suite
        , funcSuite
        ]

setMaxTests :: Int -> TestOptions -> TestOptions
setMaxTests m opts =
    case topt_maximum_generated_tests opts of
        Nothing -> opts { topt_maximum_generated_tests = Just m }
        Just _  -> opts
