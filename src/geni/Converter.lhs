% GeNI surface realiser
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

\chapter{Converter}

This module is meant to act as a standalone program which serves
strictly as a converter between the formats recognised by GenI.  The
current use is to experiment with the idea that the yacc parser for
GeniHand might be much faster than that for the TAGML format, so we
try to see if converting from TAGML to GeniHand is worthwhile.

\begin{code}
module Main (main) where
\end{code}

\ignore{
\begin{code}
import Data.FiniteMap
import Monad(when)
import System (ExitCode(ExitFailure), 
               exitWith, getArgs, getProgName)
import System.IO(getContents)

import Btypes (ifamname, iword, icategory)
import GrammarXml (parseXmlGrammar, parseXmlLexicon)
import Treeprint (toGeniHand)
\end{code}
}

\begin{code}
main :: IO ()
main = do       
  -- we take exactly one argument: a grammar index file name
  args <- getArgs
  progname <- getProgName
  let usage p = "usage: " ++ p ++ " [--macros|--lexicon] < input > output"
      showusage = do putStrLn (usage progname)
                     exitWith (ExitFailure 1)
  when (length args /= 1) showusage
  let filetype = head args
  case filetype of 
    "--macros"  -> convertMacros 
    "--lexicon" -> convertLexicon 
    _           -> showusage
\end{code}

\begin{code}
convertLexicon :: IO ()
convertLexicon = 
  do lf <- getContents 
     let lex = parseXmlLexicon lf
         showlex l = (iword l) 
                     ++ " " ++ (icategory l) ++ "\n"
                     ++ " " ++ (ifamname l) ++ "\n"
         outstr    = concatMap showlex lex
     putStr outstr 

convertMacros :: IO ()
convertMacros = 
  do gf <- getContents 
     let g = parseXmlGrammar gf 
         showfam f = "\n\n" 
                     ++ "% ----------------------------------------------------------------------"
                     ++ "\n" ++ "begin family " ++ f ++ "\n"
                     ++ "% ----------------------------------------------------------------------"
                     ++ "\n\n" ++ (concatMap toGeniHand t)
                     ++ "end family\n"
                     where t = lookupWithDefaultFM g [] f
         outstr = concatMap showfam (keysFM g)
     putStr outstr
\end{code}

