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

{-# LANGUAGE CPP #-}
module NLP.GenI.MainGui where

import Data.IORef(newIORef)
import Data.Typeable( Typeable )
import Data.Version ( showVersion )
import System.Environment(getArgs, getProgName)

import Paths_geni_gui ( version )
import NLP.GenI ( ProgState(..), emptyProgState )
import NLP.GenI.Configuration
    ( treatArgs, optionsForStandardGenI, processInstructions, usage
    , optionsSections, hasFlagP
    , BatchDirFlg(..), DumpDerivationFlg(..),  FromStdinFlg(..)
    , HelpFlg(..), VersionFlg(..)
    , readGlobalConfig, setLoggers
    )
import NLP.GenI.Console(consoleGeni)
import NLP.GenI.Gui(guiGeni)

main :: IO ()
main =  getArgs
    >>= treatArgs optionsForStandardGenI
    >>= processInstructions
    >>= (mainWithState . emptyProgState)

mainWithState :: ProgState -> IO ()
mainWithState pst = do
    pname <- getProgName
    maybe (return ()) setLoggers =<< readGlobalConfig
    pstRef <- newIORef pst
    let has :: (Typeable f, Typeable x) => (x -> f) -> Bool
        has = flip hasFlagP (pa pst)
        mustRunInConsole = has DumpDerivationFlg || has FromStdinFlg
                        || has BatchDirFlg
    case () of
      _ | has HelpFlg      -> putStrLn (usage optionsSections pname)
        | has VersionFlg   -> putStrLn ("GenI " ++ showVersion version)
        | mustRunInConsole -> consoleGeni pstRef
        | otherwise        -> guiGeni pstRef
