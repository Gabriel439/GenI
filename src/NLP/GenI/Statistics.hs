{-# LANGUAGE FlexibleContexts #-}
----------------------------------------------------
--                                                --
-- Statistics.hs:                                 --
-- Functions that collect and print out           --
-- statistics                                     --
--                                                --
----------------------------------------------------

{-
Copyright (C) GenI 2002-2005 (originally from HyLoRes)
Carlos Areces     - areces@loria.fr      - http://www.loria.fr/~areces
Daniel Gorin      - dgorin@dc.uba.ar
Juan Heguiabehere - juanh@inf.unibz.it - http://www.inf.unibz.it/~juanh/
Eric Kow          - kow@loria.fr       - http://www.loria.fr/~kow

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307,
USA.
-}

module NLP.GenI.Statistics(Statistics, StatisticsState, StatisticsStateIO,
    emptyStats,

    showFinalStats,

    initialStatisticsStateFor,
    addMetric,

    Metric(IntMetric),  queryMetrics, updateMetrics,
    incrIntMetric, queryIntMetric,
) where

import Control.Monad.State
import Data.Maybe (mapMaybe)

-------------------------------------------
-- Statistics are collections of Metrics
-- which can be printed out (at regular intervals)
-------------------------------------------
data Statistics = Stat{ metrics::[Metric] }

type StatisticsState a   = forall m. (MonadState Statistics m) => m a
type StatisticsStateIO a = forall m. (MonadState Statistics m, MonadIO m) => m a

updateMetrics :: (Metric -> Metric) -> Statistics -> Statistics
updateMetrics f stat = stat{metrics           = map f (metrics stat) }

queryMetrics :: (Metric -> Maybe a) -> Statistics -> [a]
queryMetrics f stat =  mapMaybe f (metrics stat)

mergeMetrics :: (Metric -> Metric -> Metric) -> Statistics -> Statistics -> Statistics
mergeMetrics f s1 s2 = s1 { metrics           = zipWith f (metrics s1) (metrics s2) }

--updateStep :: Statistics -> Statistics
--updateStep s@(Stat _ [] _     _)         = s
--updateStep s@(Stat _ _  _     Nothing)   = s
--updateStep stat                          = stat{count = (count stat)+1}

emptyStats :: Statistics
emptyStats = Stat []

--------------------------- Monadic Statistics functions follow ------------------------------


initialStatisticsStateFor :: (MonadState Statistics m) => (m a -> Statistics -> b) -> m a -> b
initialStatisticsStateFor f = flip f emptyStats

{- | Adds a metric at the end of the list (thus,
   metrics are printed out in the order in which they were added -}
addMetric :: Metric -> StatisticsState ()
addMetric newMetric  = modify (\stat -> stat{metrics = (metrics stat)++[newMetric]})

showFinalStats :: Statistics -> String
showFinalStats stats = unlines $ map show $ metrics stats

--------------------------------------------
-- Metrics
--------------------------------------------
data Metric = IntMetric String Int

instance Show Metric where
  show (IntMetric s x)   = s ++ " : " ++ (show x)

incrIntMetric :: String -> Int -> Metric -> Metric
incrIntMetric key i (IntMetric s c) | s == key = IntMetric s (c+i)
incrIntMetric _ _ m = m

queryIntMetric :: String -> Metric -> Maybe Int
queryIntMetric key (IntMetric s c) | s == key = Just c
queryIntMetric _ _ = Nothing
