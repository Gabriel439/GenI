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
{-# LANGUAGE FlexibleContexts, RankNTypes #-}
module NLP.GenI.Statistics(Statistics, StatisticsState,
    emptyStats,

    showFinalStats,

    initialStatisticsStateFor,
    addMetric,

    Metric(IntMetric),  queryMetrics, updateMetrics,
    incrIntMetric, queryIntMetric,
) where

import Control.Applicative ( (<$>) )
import Control.Monad.State
import Data.Maybe (mapMaybe)
import Text.JSON

import Control.DeepSeq

-------------------------------------------
-- Statistics are collections of Metrics
-- which can be printed out (at regular intervals)
-------------------------------------------
newtype Statistics = Stat{ metrics::[Metric] }

type StatisticsState a   = forall m. (MonadState Statistics m) => m a

updateMetrics :: (Metric -> Metric) -> Statistics -> Statistics
updateMetrics f stat = stat{metrics           = map f (metrics stat) }

queryMetrics :: (Metric -> Maybe a) -> Statistics -> [a]
queryMetrics f =  mapMaybe f . metrics

emptyStats :: Statistics
emptyStats = Stat []

--------------------------- Monadic Statistics functions follow ------------------------------


initialStatisticsStateFor :: (MonadState Statistics m) => (m a -> Statistics -> b) -> m a -> b
initialStatisticsStateFor f = flip f emptyStats

-- | Adds a metric at the beginning of the list
--   (note we reverse the order whene we want to print the metrics)
addMetric :: Metric -> StatisticsState ()
addMetric newMetric  = modify (\stat -> stat{metrics = newMetric : metrics stat } )

showFinalStats :: Statistics -> String
showFinalStats = unlines . map show . reverse . metrics

--------------------------------------------
-- Metrics
--------------------------------------------
data Metric = IntMetric String Int

instance Show Metric where
  show (IntMetric s x)   = s ++ " : " ++ show x

incrIntMetric :: String -> Int -> Metric -> Metric
incrIntMetric key i (IntMetric s c) | s == key = IntMetric s (c+i)
incrIntMetric _ _ m = m

queryIntMetric :: String -> Metric -> Maybe Int
queryIntMetric key (IntMetric s c) | s == key = Just c
queryIntMetric _ _ = Nothing

--------------------------- JSON Output ------------------------------

instance JSON Statistics where
    readJSON (JSObject j) = do
        Stat <$> mapM jsonToMetric (fromJSObject j)
    readJSON j = fail $
        "Expected a JSON object, but got " ++ show j ++ " instead"

    showJSON = JSObject . toJSObject . map metricToJSON . metrics

-- not quite showJSON here
metricToJSON :: Metric -> (String, JSValue)
metricToJSON (IntMetric s i) = (s, showJSON i)

jsonToMetric :: (String, JSValue) -> Result Metric
jsonToMetric (s, i) = IntMetric s <$> readJSON i

--------------------------- DeepSeq ------------------------------

{-!
deriving instance NFData Statistics
deriving instance NFData Metric
!-}


-- GENERATED START

 
instance NFData Statistics where
        rnf (Stat x1) = rnf x1 `seq` ()

 
instance NFData Metric where
        rnf (IntMetric x1 x2) = rnf x1 `seq` rnf x2 `seq` ()
-- GENERATED STOP
