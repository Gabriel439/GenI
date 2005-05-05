include declarations.mg
include semRel.mg
include grammaticalFunctionsSem.mg
include verbesSem.mg
include functionwordsSem.mg
include adjectifsSem.mg
include nomsSem.mg
include lexique.mg
%include verbes.mg
%include adjectifs.mg

%include adverbes.mg
%include misc.mg

 
% VALUATION
%%%%%%%%%%%%


%% calls

%Impersonal
%value ilV		%il pleut
%value ilVcs1		%il faut que Jean vienne/venir

%Nominal
%value n0V 		%Jean dort			15 trees
%value n0ClV		%Jean s'�vanouit		8 trees
value n0Vn1		%Jean regarde Marie		165 trees > 107
value n0Van1		%Jean parle � Marie		65 trees

value n0ClVn1		%L'enfant s'appelle Marie	35 trees

value n0Vden1		%Jean parle de ses vacances	47 trees
value n0ClVden1		%Jean se souvient de Marc	47 trees
value n0Vpn1		%Jean parle avec Marie		33 trees
value n0ClVpn1		%Jean se bat contre Paul	33 trees
value n0Vloc1		%Jean va � Paris		29 trees
value n0Vn1an2		%Jean donne un cadeau � Marie

%value n0Van1den2	%Jean parle de ses vacances � Marie
%value n0Vn1den2		%Jean re�oit un cadeau de Marie
%value n0Vden1pn2	%Jean parle de ce livre avec Marie
%value n0Vn1loc2		%Jean envoie la lettre � la poste	-- 629 trees

%% Noms

value propername
value commonNoun
value CliticT
value pronoun

% Function words
value stddeterminer
value prepositionN

% Adjectifs
value adjectifEpithete

% Lexique
value aime
value plaire