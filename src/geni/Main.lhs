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

\chapter{Main}

Welcome to the GenI source code.  The main module is where everything
starts from.  If you're trying to figure out how GenI works, the main
action is in Geni and Tags 
(chapters \ref{cha:Geni} and \ref{cha:Tags}).  

\begin{code}
module Main (main) where
\end{code}

\ignore{
\begin{code}
import Data.IORef(newIORef)
import System(getArgs)
import qualified Data.Map as Map

import Geni(ProgState(..))
import Console(consoleGenerate)
import Configuration(treatArgs, isGraphical, isBatch, Params)

#ifndef DISABLE_GUI
import Gui(guiGenerate)
#else
guiGenerate = consoleGenerate
#endif
\end{code}
}

In figure \ref{fig:code-outline-main} we show what happens from main: First, we
hand control off to either the console or the graphical user interface.  These
functions then do all the business stuff like loading files and figuring out
what to generate.  From there, they invoke the the generation step
\fnreflite{runGeni}.  The function runGeni takes an argument which determines
how exactly to run the generator.  For more details, see page
\pageref{fn:runGeni}.

\begin{figure}
\begin{center}
\includegraphics[scale=0.25]{images/code-outline-main}
\label{fig:code-outline-main}
\caption{How the GenI entry point is used}
\end{center}
\end{figure}

\begin{code}
main :: IO ()
main = do       
  args     <- getArgs
  confArgs <- treatArgs args
  pstRef   <- newIORef (emptyProgState confArgs)
  let notBatch  = not (isBatch confArgs)
      graphical = isGraphical confArgs 
  if (graphical && notBatch) 
     then guiGenerate pstRef
     else consoleGenerate pstRef
\end{code}

\paragraph{emptyProgState} is the program state when you start GenI for the very first time

\begin{code}
emptyProgState :: Params -> ProgState
emptyProgState args = 
 ST { pa = args 
    , gr = []
    , le = Map.empty
    , morphinf = const Nothing
    , ts = ([],[])
    , tcase = []
    , tsuite = [] }
\end{code}

% TODO
% Define what is and what is not exported from the modules.  
%      In particular in BTypes take care to export the inspection function 
%      but not the types.
%      Re-write functions in Main as needed.
% Change input in Lexicon and Grammar to allow more than one anchor.
% Keys used in Tags are specially bad for Pn, perhaps they can be improved.
