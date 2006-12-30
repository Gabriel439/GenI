% GenI surface realiser
% Copyright (C) 2005 Carlos Areces and Eric Kow
%
% This program is free software; you can redistribute it and/or
% modify it under the terms of the GNU General Public License
% as published by the Free Software Foundation; either version 2
% of the License, or (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program; if not, write to the Free Software
% Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

\chapter{ExtractTestCases}

This is a standalone program that provides a simple interface to the
test suite parser. 

The idea is that you give it a directory.  For each test case in the
suite, it creates a subdirectory (with the test case name) and in 
that subdirectory, it creates two files containing the semantics and
the sentences.

The purpose of this program is to serve as helper module for tools 
that batch-test GenI.

\begin{code}
module Main (main) where

import NLP.GenI.Btypes
import NLP.GenI.General ((///), ePutStrLn)
import NLP.GenI.GeniParsers(geniTestSuite, geniTestSuiteString, toSemInputString)
import NLP.GenI.GeniShow (GeniShow(geniShow))
import Data.List(nubBy,sort)
import System.Directory
import System.Environment
import System.Exit(exitFailure)
import System.IO
import Text.ParserCombinators.Parsec 
\end{code}

\begin{code}
main :: IO ()
main = 
 do (tfilename, outdir) <- readArgv
    -- parse the test suite
    suite'   <- getParseFromFile geniTestSuite tfilename 
    caseStrs <- getParseFromFile geniTestSuiteString tfilename
    -- process the suite
    -- (for now, just remove redundant entries)
    let canon = srt . tcSem
          where srt (sem,res,lc) = (sortSem sem, sort res, sort lc)
        suite = nubBy (\x y -> canon x == canon y) $ zipWith setStr suite' caseStrs
          where setStr tc s = tc { tcSemString = s }
    -- write stuff to the output directory
    createDirectoryIfMissing False outdir
    mapM_ (createSubdir outdir) suite
 where
  readArgv =
    do argv <- getArgs
       case argv of
         [x1,x2] -> return (x1, x2)
         _       -> showUsage
  showUsage =
    do pname <- getProgName
       ePutStrLn err_
       exitFailure
    
createSubdir :: String -> TestCase -> IO ()
createSubdir outdir (TestCase { tcName = name
                              , tcSemString = semStr
                              , tcSem =  semInput
                              , tcExpected = sent}) =
 do let subdir = outdir /// name
    createDirectoryIfMissing False subdir
    --
    writeFile (subdir /// "semantics") $ geniShow $
      toSemInputString semInput semStr
    writeFile (subdir /// "sentences") $ unlines sent
\end{code}

\begin{code}
getParseFromFile :: Parser b -> FilePath -> IO b
getParseFromFile p f =
  parseFromFile p f >>= either exitShowing return

exitShowing :: (Show a) => a -> IO b
exitShowing err=
 do let err_ = show err
    ePutStrLn err_
    exitFailure
\end{code}

