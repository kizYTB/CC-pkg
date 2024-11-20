-- URL du dépôt GitHub contenant le fichier JSON des paquets
local REPO_URL = "https://raw.githubusercontent.com/kizYTB/CC-pkg/refs/heads/main/packages.json"

-- Fonction pour télécharger et lire le fichier JSON des paquets
local function fetchPackageList()
    local response = http.get(REPO_URL)
    if not response then
        error("Impossible de récupérer la liste des paquets depuis le dépôt.")
    end
    local data = response.readAll()
    response.close()
    local ok, result = pcall(textutils.unserializeJSON, data)
    if not ok then
        error("Erreur de lecture du fichier JSON.")
    end
    return result
end

-- Fonction pour installer un paquet
local function installPackage(packageName, installed)
    installed = installed or {} -- Pour éviter d'installer deux fois la même dépendance
    print("Recherche du paquet : " .. packageName)
    local packages = fetchPackageList()
    local package = packages["packages"][packageName]
    
    if not package then
        error("Paquet introuvable : " .. packageName)
    end

    -- Vérifie si la dépendance est déjà installée
    if installed[packageName] then
        return
    end

    -- Résolution des dépendances
    if package["dependencies"] then
        for _, dependency in ipairs(package["dependencies"]) do
            print("Installation de la dépendance : " .. dependency)
            installPackage(dependency, installed)
        end
    end

    -- Exécute la commande d'installation
    print("Installation de " .. packageName .. "...")
    shell.run(package["install"])
    installed[packageName] = true -- Marque le paquet comme installé
    print(packageName .. " installé avec succès.")
end

-- Fonction pour lister tous les paquets disponibles
local function listPackages()
    print("Liste des paquets disponibles :")
    local packages = fetchPackageList()["packages"]
    for name, info in pairs(packages) do
        print("- " .. name .. ": " .. info["description"])
    end
end

-- Fonction CLI principale
local function main(args)
    if #args < 1 then
        print("Usage :")
        print("  pkg install <package_name> - Installe un paquet")
        print("  pkg list                  - Liste tous les paquets disponibles")
        return
    end
    
    local command = args[1]
    
    if command == "install" then
        if not args[2] then
            print("Veuillez spécifier le nom du paquet à installer.")
            return
        end
        local packageName = args[2]
        local ok, err = pcall(function()
            installPackage(packageName)
        end)
        if not ok then
            print("Erreur : " .. err)
        end
    elseif command == "list" then
        listPackages()
    else
        print("Commande inconnue. Utilisez 'install <package>' ou 'list'.")
    end
end

-- Exécution du gestionnaire de paquets depuis la CLI
local args = {...}
main(args)

