{-
geniserver
Copyright (C) 2011 Eric Kow (on behalf of SRI)

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
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
-}

module NLP.GenI.Server.Instruction (ServerInstruction(..))
where

import Control.Applicative ( (<$>), (<*>) )
import Text.JSON

data ServerInstruction = ServerInstruction
  { gParams    :: [String]
  , gSemantics :: String
  }

instance JSON ServerInstruction where
 readJSON j =
    do jo <- fromJSObject `fmap` readJSON j
       let fieldOr def x = maybe def readJSON (lookup x jo)
           fieldOrNull   = fieldOr (return [])
           field x       = fieldOr (fail $ "Could not find: " ++ x) x
       ServerInstruction <$> fieldOrNull "params"
                         <*> field "semantics"
 showJSON x =
     JSObject . toJSObject $ [ ("params", showJSONs $ gParams x)
                             , ("semantics", showJSON $ gSemantics x)
                             ]
