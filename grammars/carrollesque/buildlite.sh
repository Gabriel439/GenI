MetaTAG --xml -o semFrenchLite.xml semFrenchLite.mg 
rm semFrenchLite.geni
../../geniconvert --macros < semFrenchLite.xml > semFrenchLite.geni
