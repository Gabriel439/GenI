include gram/cgTAG.mg

% VALUATION
%%%%%%%%%%%%%%%%%%%%%%%%%

value PrepositionN

%Nominal
value ilV		%il pleut
value n0V 		%Jean dort
value n0Vn1		%Jean regarde Marie
value s0Vn1
value n0Vn1an2		%Jean donne un cadeau � Marie

value n0ClV		%Jean s'�vanouit
value n0ClVn1		%L'enfant s'appelle Marie
value n0Van1		%Jean parle � Marie
value n0Vden1		%Jean parle de ses vacances
value n0ClVden1		%Jean se souvient de Marc
value n0Vpn1		%Jean parle avec Marie
value n0ClVpn1		%Jean se bat contre Paul
value n0Vloc1		%Jean va � Paris
value n0Van1des2_0	%Jean promet � Marie de venir 
			% subject control
value n0Vn1des2_1	%Jean persuade Marie de venir 
			% subject control
%value n0Van1des2	%Jean promet � Marie qu'il partira
value noVinf		% partir

% PREDICATIVE ADJECTIVES
value n0vApre  % un heureux �v�nement
value n0vApost % un gar�on heureux
value n0vA		%Jean est heureux, un gar�on heureux, un heureux �v�nement
value s0vA		%Que Marie parte �tait impr�vu, Le d�part impr�vu
value n0vAden1		%Le p�re est fier de sa fille, un p�re fier de sa fille
value n0vAan1		%L'enfant est attentif � ce projet, L'enfant attentif � ce projet
value n0vApn1		%Un enfant fort en maths, L'enfant est fort en maths
value n0vAan1pn2	%Un enfant sup�rieur � Luc en math, Cet enfant est sup�rieur � Luc en maths
value n0vAan1den2	%Un ami redevable � Paul de ses conseils, Ce bonhomme est redevable � Paul de ses conseils

%PREDICATIVE NOUNS
value n0vN		%Jean , La *France*, Jean est un *gar�on*
value n0vNan1		%  
value n0vNden1		%Marie est la *femme* de Jean; La *femme* de Jean s'appelle Marie

%NonVerbalVerbs (!)
value AvoirAux		%Jean *a* mang�
value EtreAux		%Jean *est* venu
value SemiAux		%Jean *semble* partir
value Copule		%Jean *est* aim� par Marie

% TOUGH adjectives
%(only subject to subject raising)
value toughDe		%Il est susceptible de pleuvoir


% Adverbs
%value advArgMan	%Jean court vite / *Jean court
value advLoc		%Les enfants viennent *ici*, *O� vont les enfants*
value prepLoc		%Dans quelle ville vont les enfants, les enfants vont chez la m�re grand
value advSAnte          %Hier Jean est venu, *jean hier est venu, *jean est hier venu,...
value advSPost		%Jean viendra demain *jean est demain venu...
value advVPost		%Jean a vraiment vu un monstre !
value advAdjAnte	%Jean est tr�s petit
value advAdvAnte	%Jean court tr�s vite
% PPModifiers
value s0Pcs1		%Jean veut qu'on se rencontre avant le match,que tu partes, de partir
value s0Ps1		%Jean veut qu'on se rencontre apr�s le match,que tu partes, apr�s �tre partis
value s0PLoc1		%Nous viendrons jusque chez vous
value s0Pn1		%Un livre avec une couverture bleue

% Misc.
value CliticT		%Tree for any clitic : Jean *le* donne
value InvertedSubjClitic%Tree for inverted subject clitic in context of questions : Semble*-t-il* venir ? Viendra*-t-il* ?
value Subjclitic	  %Tree for clitic subject (je,tu,il,elle,on,ce,nous,vous,ils,elles)
%value PrepositionalPhrase %Tree for postnominal PP modifier
value propername	%Marie
value commonNoun        %chat
value n0Nmod		%monsieur *Machin*
value stddeterminer	%*Le* lutin
value whdeterminer	%*Quel* lutin
value Coordination	%Any simple constituent coordination :Jean *et* Marie mangent

%negative hack :-(
%A truly dirty hack requested for Evalda (see above) 
value negLeft		%ne implemented as adjunct >-(    Jean ne vient pas
value negPas		%pas implemented as adjunct >-(   Jean ne mange pas, Jean ne mange gu�re...
% really a shame...


%EVALDA FEEDBACK

% participe pr�sent :

% (priorit� faible) les coteaux environnant la ville 

% 4) Attributs 
%-> Attribut de l'objet

%???? Elle traite Jean d'imb�cile (Elle traite Jean de Jean �tre un imb�cile)
%
%???? La plus belle de la collection est la verte 

%???? Certains enseignants se d�clarent choqu�s

%en quelle ann�e a-t-on vraiment construit la premi�re automobile ?

% D�terminants quantifieurs
%une centaine de -> 2 familles ? think more about this...
%beaucoup de     ->
%trop de         ->

% La solution retenue fut celle propos�e par Jean
% La solution fut propos�e de telle sorte que tt le monde soit d'accord.
