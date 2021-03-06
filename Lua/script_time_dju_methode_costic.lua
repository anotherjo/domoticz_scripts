--[[   
~/domoticz/scripts/lua/script_time_dju_methode_costic.lua
auteur : papoo
MAJ : 27/12/2018
création : 29/01/2018
Principe :
Calculer, via l'information température d'une sonde extérieure, les Degrés jour Chauffage méthode COSTIC

Création automatique du device compteur et des variables nécessaire au fonctionnement de ce script.
Seul pré-requis à la création d'un device par ce script, l'existence d'un hardware dummy dans votre domoticz.
Pour cela, uploadez ou créez ce script dans le répertoire domoticz/scripts/lua/ 
éditer éventuellement les noms des devices à créer, passez la variable script_actif à true, sauvegardez et vérifiez vos logs.

Un degré jour est calculé à partir des températures météorologiques extrêmes du lieu et du jour J : 
- Tn : température minimale du jour J mesurée à 2 mètres du sol sous abri et relevée entre J-1 (la veille) à 18h et J à 18h UTC. 
- Tx : température maximale du jour J mesurée à 2 mètres du sol sous abri et relevée entre J à 6h et J+1 (le lendemain) à 6h UTC. 
- S : seuil de température de référence choisi. 
- Moy = (Tn + Tx)/2 Température Moyenne de la journée
Pour un calcul de déficits  de température par rapport au seuil choisi : 
- Si S > TX (cas fréquent en hiver) : DJ = S - Moy 
- Si S ≤ TN (cas exceptionnel en début ou en fin de saison de chauffe) : DJ = 0 
- Si TN < S ≤ TX (cas possible en début ou en fin de saison de chauffe) : DJ = ( S – TN ) * (0.08 + 0.42 * ( S –TN ) / ( TX – TN ))


https://github.com/papo-o/domoticz_scripts/blob/master/Lua/script_time_dju_methode_costic.lua
https://pon.fr/calcul-de-dju-methode-costic/
http://easydomoticz.com/forum/viewtopic.php?f=17&t=5984
--]]
--------------------------------------------
------------ Variables à éditer ------------
-------------------------------------------- 
local debugging = false  			    -- true pour voir les logs dans la console log Dz ou false pour ne pas les voir
local script_actif = true                           -- active (true) ou désactive (false) ce script simplement
local temp_ext  = 'Temperature exterieure' 	    -- nom de la sonde de température extérieure
local domoticzURL = '127.0.0.1:8080'                -- user:pass@ip:port de domoticz
local var_user_djc = 'dju_methode_costic'           -- nom de la variable utilisateur de type 2 (chaine) pour le stockage temporaire des données journalières DJC
local Tn = "Tn_methode_costic"                      -- température maximale du jour J relevée entre J à 6h et J+1 (le lendemain) à 6h UTC
local Tx = "Tx_methode_costic"                      -- température minimale du jour J relevée entre J-1 (la veille) à 18h et J à 18h UTC.
local Tn_hold = "Tn_Hold_methode_costic"            -- variable de stockage de la température mini.
local S = 18                                        -- seuil de température de non chauffage, par convention : 18°C
local cpt_djc = 'DJU méthode COSTIC' 		    -- nom du  dummy compteur DJC en degré


--------------------------------------------
----------- Fin variables à éditer ---------
-------------------------------------------- 
commandArray = {}
local nom_script = 'Calcul Degrés jour Chauffage méthode COSTIC'
local version = '1.03'
local id
local djc

time=os.date("*t")
package.path = package.path..";/home/pi/domoticz/scripts/lua/fonctions/?.lua"   
require('fonctions_perso')                                                      

--------------------------------------------
-------------- Fin Fonctions ---------------
-------------------------------------------- 
if script_actif == true then
    voir_les_logs("========= ".. nom_script .." (v".. version ..") =========",debugging)
    if otherdevices[cpt_djc] == nil then
        -- recherche d'un hardware dummy pour l'associer au futur compteur
    	local config = assert(io.popen(curl..'"'.. domoticzURL ..'/json.htm?type=hardware" &'))
        local blocjson = config:read('*all')
        config:close()
        local jsonValeur = json:decode(blocjson)
			if jsonValeur ~= nil then
			   for Index, Value in pairs( jsonValeur.result ) do
                   if Value.Type == 15 then -- hardware dummy = 15
                      voir_les_logs("--- --- --- idx hardware dummy  : ".. Value.idx .." --- --- ---",debugging)
                      voir_les_logs("--- --- --- Nom hardware dummy  : ".. Value.Name .." --- --- ---",debugging)                  
                      id = Value.idx
                   end  
			   end
			end
        if id ~= nil then 
            voir_les_logs("--- --- --- création du device RFXMeter  : ".. cpt_djc .. " --- --- ---",debugging) 
            os.execute(curl..'"'.. domoticzURL ..'/json.htm?type=createvirtualsensor&idx='..id..'&sensorname='..url_encode(cpt_djc)..'&sensortype=113"')                      
        end
    else     
        local attribut = DeviceInfos(cpt_djc)
        if attribut then
            if attribut.SwitchTypeVal == 0 then
                voir_les_logs("--- --- --- modification du device RFXMeter  : ".. cpt_djc .. " en compteur de type 3  --- --- ---",debugging) 
                os.execute(curl..'"'.. domoticzURL ..'/json.htm?type=setused&idx='..otherdevices_idx[cpt_djc]..'&name='..url_encode(cpt_djc)..'&switchtype=3&used=true"')
            end
        else
            voir_les_logs("--- --- --- impossible d\'extraire les caractéristiques du compteur ".. cpt_djc .."  --- --- ---",debugging)
        end
    end -- if otherdevices[cpt_djc]
    
    -- calcul DJCvoir_les_logs("--- --- --- Température Ext : "..temperature,debugging) 
    if otherdevices_svalues[temp_ext] ~= nil then
     
        if (uservariables[Tx] == nil) then creaVar(Tx,2,"-150")end
        if (uservariables[Tn] == nil) then creaVar(Tn,2,150)end
        if (uservariables[Tn_hold] == nil) then creaVar(Tn_hold,2,150)end
        
        if (uservariables[Tx] ~= nil) and (uservariables[Tn] ~= nil) and (uservariables[Tn_hold] ~= nil) then
            --temperature = tonumber(string.match(otherdevices_svalues[temp_ext], "%d+%.*%d*"))
            temperature = tonumber(string.match(otherdevices_svalues[temp_ext], "%-?%d+%.*%d*"))
            voir_les_logs("--- --- --- Température Ext : "..temperature,debugging)
            voir_les_logs("--- --- ---  Tn : "..uservariables[Tn],debugging)
            voir_les_logs("--- --- ---  Tx : "..uservariables[Tx],debugging)
            voir_les_logs("--- --- --- Tn_hold : "..uservariables[Tn_hold],debugging)
            if temperature < S then --si la température extérieure est inférieure au seuil S défini dans les variables
            voir_les_logs("--- --- --- Température Extérieure inférieure au seuil de ".. S .."°c",debugging)
                if temperature < tonumber(uservariables[Tn]) then
                    voir_les_logs("--- --- --- Température Extérieure inférieure à Variable Tn : "..uservariables[Tn],debugging)
                    commandArray[#commandArray+1] = {['Variable:'.. Tn] = tostring(temperature)} -- mise à jour de la variable tn
                    voir_les_logs("--- --- --- mise à jour de la Variable Tn  --- --- --- ",debugging)
                elseif temperature > tonumber(uservariables[Tx]) then
                    voir_les_logs("--- --- --- Température Extérieure supérieure à Variable Tx : "..uservariables[Tx],debugging)
                    commandArray[#commandArray+1] = {['Variable:'.. Tx] = tostring(temperature)} -- mise à jour de la variable tx
                    voir_les_logs("--- --- --- mise à jour de la Variable Tx  --- --- --- ",debugging)	
                end
            end    
        end
    else
        voir_les_logs("--- --- le device : ".. temp_ext .." n\'existe pas --- ---",debugging)
    end -- fin si otherdevices_svalues[temp_ext] ~= nil 

if (time.min == 0 and time.hour == 2) then 
local temp_mini = tonumber(uservariables[Tn])
    commandArray[#commandArray+1] = {['Variable:'.. Tn_hold] = tostring(temp_mini)} -- mise à jour de la variable Tn_hold
    commandArray[#commandArray+1] = {['Variable:'.. Tn] = tostring(150)} -- ré-initialisation de la variable Tn
end
if (time.min == 01 and time.hour == 18) then 
    local temp_mini_hold = tonumber(uservariables[Tn_hold])
    if temp_mini ~= 150 then
        local temp_maxi = tonumber(uservariables[Tx])
        voir_les_logs("--- --- --- Tx ("..temp_maxi.."°C)  --- --- --- ",debugging)
        local moyenne = tonumber((temp_mini_hold + temp_maxi)/2)
        voir_les_logs("--- --- --- Moyenne ("..moyenne.."°C)  --- --- --- ",debugging)
        S = tonumber(S)

        if S > temp_maxi then
            djc = round(S - moyenne,0)
        voir_les_logs("--- --- --- Le Seuil de "..S.."°C est superieur a Tx ("..temp_maxi.."°C)  --- --- --- ",debugging)   
        voir_les_logs("--- --- --- Le Seuil de "..S.."°C est inferieur ou egal a Tn_hold ("..temp_mini_hold.."°C)  --- --- --- ",debugging)
        voir_les_logs("--- --- --- djc : "..djc,debugging)
        elseif temp_mini_hold < S and S < temp_maxi then 
            local a = S - temp_mini_hold
            voir_les_logs("--- --- --- a : "..a,debugging)
            local b = temp_maxi - temp_mini_hold
            voir_les_logs("--- --- --- b : "..b,debugging)
            djc = a * ( 0.08 + 0.42 * a / b )
            voir_les_logs("--- --- --- djc : "..djc,debugging)
            djc = round(djc,0)
            --djc = ( S – temp_mini_hold ) * (0.08 + 0.42 * ( S – temp_mini_hold ) / ( temp_maxi – temp_mini_hold ) )
            voir_les_logs("--- --- --- Le Seuil de "..S..")C est superieur a Tx ("..temp_maxi.."°C) est inferieur a Tn_hold  ("..temp_mini_hold.."°C)--- --- --- ",debugging)
        elseif S <= temp_mini_hold then
            djc = 0
        end
        local cpt_djc_index = otherdevices_svalues[cpt_djc]
        voir_les_logs("--- --- --- compteur avant mise à jour ".. cpt_djc .." : ".. cpt_djc_index .." DJU",debugging)
        cpt_djc_index = tonumber(cpt_djc_index) + djc
        voir_les_logs("--- --- --- mise à jour compteur ".. cpt_djc .." : ".. cpt_djc_index .." DJU",debugging)
        commandArray[#commandArray+1] = {['UpdateDevice'] = otherdevices_idx[cpt_djc] .. '|0|'..tostring(cpt_djc_index)} --mise à jour du compteur
        commandArray[#commandArray+1] = {['Variable:'.. Tx] = tostring(-150)} -- mise à jour de la variable Tx
    else
        voir_les_logs("--- --- --- Calcul impossible, il n\'y a pas de Température minimum enregistrée, attendre le prochain calcul",debugging)
    end
end

    -- fin calcul DJC
    -- --==============================================================================================

    voir_les_logs("======= Fin ".. nom_script .." (v".. version ..") =======",debugging)
end
return commandArray
