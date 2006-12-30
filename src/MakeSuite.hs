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

-- This standalone program is a counterpart to geniextract.

-- We have a little bit of sneakiness here: the sentence keyword
-- is optional, so we exploit this fact to visually distinguish
-- between expected test cases (sentence), and results produced
-- by the generator.  If you read the resulting test suite in
-- GenI, both are interpreted as expected output.

module Main (main) where

import NLP.GenI.Btypes
import NLP.GenI.General (basename, comparing, (///), ePutStrLn, readFile', toAlphaNum)
import NLP.GenI.GeniParsers(geniSemanticInput)
import NLP.GenI.GeniShow (GeniShow(geniShow))

import Data.List (sortBy)
import qualified Data.Map as Map
import Data.Maybe(catMaybes)
import System.Directory
import System.Environment
import System.Exit(exitFailure)
import System.IO
import Text.ParserCombinators.Parsec

main :: IO ()
main =
 do (eDir, rDir) <- readArgv
    cases     <- readSubDirsWith readExtracted eDir
    responses <- readSubDirsWith readResponses rDir
    let responseMap = Map.fromList responses
        showCase = geniShow.getExtra
        getExtra c = case Map.lookup (tcName c) responseMap of
                        Nothing -> c
                        Just rs -> c { tcOutputs = rs }
        sortAlphaNum = sortBy (comparing $ toAlphaNum.tcName)
    putStrLn . unlines . map showCase . sortAlphaNum $ cases
 where
  readArgv =
    do argv <- getArgs
       case argv of
         [x1,x2] -> return (x1, x2)
         _    -> showUsage
  showUsage =
    do pname <- getProgName
       ePutStrLn  $ "usage: " ++ pname ++ " testDir responsesDir"
       exitFailure
  readSubDirsWith r d =
    do subdirs <- getDirectoryContents d
       catMaybes `fmap` mapM (r d) subdirs

readExtracted :: FilePath -> FilePath -> IO (Maybe TestCase)
readExtracted parentdir subdir =
 do semanticsE <- doesFileExist semanticsF
    sentencesE <- doesFileExist sentencesF
    if semanticsE && sentencesE
       then do sentences <- lines `fmap` readFile' sentencesF
               semantics <- getParse =<< parseFromFile geniSemanticInput semanticsF
               return . Just $ TestCase
                 { tcName = basename subdir
                 , tcSemString = ""
                 , tcSem  = semantics
                 , tcExpected = sentences
                 , tcOutputs = []
                 }
       else return Nothing
 where
  semanticsF = parentdir /// subdir /// "semantics"
  sentencesF = parentdir /// subdir /// "sentences"

readResponses :: FilePath -> FilePath -> IO (Maybe (String, [String]))
readResponses parentdir subdir =
 do overgensE <- doesFileExist overgensF
    if overgensE
       then do os <- lines `fmap` readFile' overgensF
               return . Just $ (subdir, os)
       else return Nothing
 where
  overgensF  = parentdir /// subdir /// "responses"

getParse :: (Show a) => Either a b -> IO b
getParse = either exitShowing return

exitShowing :: (Show a) => a -> IO b
exitShowing err=
 do let err_ = show err
    ePutStrLn err_
    exitFailure


