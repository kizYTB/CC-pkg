-- CC-PKG : Gestionnaire de paquets pour ComputerCraft
-- Par kizYTB

local REPO_URL = "https://raw.githubusercontent.com/kizYTB/CC-pkg/refs/heads/main/packages.json"
local CONFIG_DIR = "/.cc-pkg"
local APPS_DIR = "/.cc-pkg/apps"
local CONFIG_FILE = "/.cc-pkg/config.json"
local LOG_FILE = "/.cc-pkg/cc-pkg.log"

-- Utilitaires
local function log(msg)
    local file = fs.open(LOG_FILE, "a")
    if file then
        file.write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(msg) .. "\n")
        file.close()
    end
end

local function ensureDirectories()
    if not fs.exists(CONFIG_DIR) then fs.makeDir(CONFIG_DIR) end
    if not fs.exists(APPS_DIR) then fs.makeDir(APPS_DIR) end
end

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then
        local defaultConfig = {
            autoUpdate = true,
            checkUpdates = true,
            lastUpdateCheck = 0,
            installed = {}
        }
        local file = fs.open(CONFIG_FILE, "w")
        file.write(textutils.serialize(defaultConfig))
        file.close()
        return defaultConfig
    end
    
    local file = fs.open(CONFIG_FILE, "r")
    local config = textutils.unserialize(file.readAll())
    file.close()
    return config
end

local function saveConfig(config)
    local file = fs.open(CONFIG_FILE, "w")
    file.write(textutils.serialize(config))
    file.close()
end

local function parseVersion(version)
    local major, minor, patch = version:match("(%d+)%.(%d+)%.(%d+)")
    return {
        major = tonumber(major) or 0,
        minor = tonumber(minor) or 0,
        patch = tonumber(patch) or 0
    }
end

local function isVersionGreaterOrEqual(v1, v2)
    if v1.major > v2.major then return true end
    if v1.major < v2.major then return false end
    if v1.minor > v2.minor then return true end
    if v1.minor < v2.minor then return false end
    return v1.patch >= v2.patch
end

local function checkCompatibility(package)
    -- Vérifier la version de CC
    if package.compatibility and package.compatibility.requires then
        local req = package.compatibility.requires
        
        -- Vérifier la version de CC
        if req.ccversion then
            local current = os.version()
            if current < req.ccversion then
                return false, "Nécessite CC version " .. req.ccversion .. " ou supérieur"
            end
        end
        
        -- Vérifier le terminal couleur
        if req.term == "color" and not term.isColor() then
            return false, "Nécessite un terminal couleur"
        end
        
        -- Vérifier la mémoire
        if req.memory then
            local free = os.getComputerID() -- À remplacer par une vraie vérification de mémoire
            if free < tonumber(req.memory:match("(%d+)")) then
                return false, "Mémoire insuffisante"
            end
        end
        
        -- Vérifier les périphériques
        if req.peripheral then
            for _, p in ipairs(req.peripheral) do
                if not peripheral.find(p) then
                    return false, "Périphérique requis manquant: " .. p
                end
            end
        end
    end
    
    return true
end

-- Fonctions principales
local function fetchPackageList()
    local response = http.get(REPO_URL)
    if not response then
        return nil, "Impossible de récupérer la liste des paquets"
    end
    local data = response.readAll()
    response.close()
    
    local ok, result = pcall(textutils.unserializeJSON, data)
    if not ok then
        return nil, "Erreur de lecture du fichier JSON"
    end
    return result
end

local function installPackage(packageName, config)
    log("Installation de " .. packageName)
    print("Recherche du paquet " .. packageName .. "...")
    
    local packages = fetchPackageList()
    if not packages then
        return false, "Impossible de récupérer la liste des paquets"
    end
    
    local package = packages.packages[packageName]
    if not package then
        return false, "Paquet introuvable"
    end
    
    -- Vérifier la compatibilité
    local compatible, reason = checkCompatibility(package)
    if not compatible then
        return false, "Incompatible: " .. reason
    end
    
    -- Installer les dépendances
    if package.dependencies then
        for _, dep in ipairs(package.dependencies) do
            if not config.installed[dep] then
                print("Installation de la dépendance: " .. dep)
                local success, err = installPackage(dep, config)
                if not success then
                    return false, "Erreur d'installation de la dépendance " .. dep .. ": " .. (err or "")
                end
            end
        end
    end
    
    -- Créer le dossier de l'application
    local appDir = fs.combine(APPS_DIR, packageName)
    if not fs.exists(appDir) then
        fs.makeDir(appDir)
    end
    
    -- Installer le paquet
    print("Installation de " .. packageName .. "...")
    
    -- Sauvegarder les métadonnées
    local metadata = {
        name = package.name or packageName,
        version = package.version or "1.0.0",
        description = package.description,
        installDate = os.epoch("local"),
        author = package.author,
        category = package.category
    }
    
    local metaFile = fs.combine(appDir, "package.json")
    local file = fs.open(metaFile, "w")
    file.write(textutils.serializeJSON(metadata))
    file.close()
    
    -- Exécuter l'installation
    local oldDir = shell.dir()
    shell.setDir(appDir)
    
    local success, err = pcall(function()
        shell.run(package.install)
    end)
    
    shell.setDir(oldDir)
    
    if not success then
        fs.delete(appDir)
        return false, "Erreur d'installation: " .. tostring(err)
    end
    
    -- Mettre à jour la configuration
    config.installed[packageName] = metadata
    saveConfig(config)
    
    print(packageName .. " installé avec succès!")
    return true
end

local function uninstallPackage(packageName, config)
    log("Désinstallation de " .. packageName)
    
    if not config.installed[packageName] then
        return false, "Paquet non installé"
    end
    
    -- Vérifier les dépendances inverses
    for name, info in pairs(config.installed) do
        if info.dependencies and info.dependencies[packageName] then
            return false, name .. " dépend de ce paquet"
        end
    end
    
    local appDir = fs.combine(APPS_DIR, packageName)
    
    -- Exécuter le script de désinstallation s'il existe
    local uninstallScript = fs.combine(appDir, "uninstall.lua")
    if fs.exists(uninstallScript) then
        local oldDir = shell.dir()
        shell.setDir(appDir)
        shell.run(uninstallScript)
        shell.setDir(oldDir)
    end
    
    -- Supprimer le dossier
    fs.delete(appDir)
    
    -- Mettre à jour la configuration
    config.installed[packageName] = nil
    saveConfig(config)
    
    print(packageName .. " désinstallé avec succès!")
    return true
end

local function listPackages(showInstalled)
    local packages = fetchPackageList()
    if not packages then
        print("Impossible de récupérer la liste des paquets")
        return
    end
    
    local config = loadConfig()
    
    -- Afficher les catégories
    if packages.categories then
        term.setTextColor(colors.yellow)
        print("=== Catégories ===")
        term.setTextColor(colors.white)
        for name, desc in pairs(packages.categories) do
            print(name .. ": " .. desc)
        end
        print()
    end
    
    term.setTextColor(colors.cyan)
    print("=== Paquets disponibles ===")
    term.setTextColor(colors.white)
    
    -- Trier les paquets par catégorie
    local byCategory = {}
    for name, info in pairs(packages.packages) do
        local cat = info.category or "other"
        byCategory[cat] = byCategory[cat] or {}
        table.insert(byCategory[cat], {name = name, info = info})
    end
    
    -- Afficher les paquets
    for category, pkgs in pairs(byCategory) do
        term.setTextColor(colors.yellow)
        print("\n" .. category:upper())
        term.setTextColor(colors.white)
        
        table.sort(pkgs, function(a, b) return a.name < b.name end)
        
        for _, pkg in ipairs(pkgs) do
            local name, info = pkg.name, pkg.info
            local installed = config.installed[name]
            
            if not showInstalled or installed then
                if installed then
                    term.setTextColor(colors.green)
                    write("[Installé] ")
                else
                    term.setTextColor(colors.white)
                end
                
                write(name)
                if info.version then
                    write(" (v" .. info.version .. ")")
                end
                print(": " .. (info.description or ""))
                
                if info.author then
                    term.setTextColor(colors.gray)
                    print("  Auteur: " .. info.author)
                end
                
                if info.dependencies and #info.dependencies > 0 then
                    term.setTextColor(colors.gray)
                    print("  Dépendances: " .. table.concat(info.dependencies, ", "))
                end
            end
        end
    end
    
    term.setTextColor(colors.white)
end

local function searchPackages(query)
    local packages = fetchPackageList()
    if not packages then
        print("Impossible de récupérer la liste des paquets")
        return
    end
    
    local config = loadConfig()
    local found = false
    
    term.setTextColor(colors.cyan)
    print("=== Résultats pour '" .. query .. "' ===")
    term.setTextColor(colors.white)
    
    for name, info in pairs(packages.packages) do
        if name:lower():find(query:lower()) or 
           (info.description and info.description:lower():find(query:lower())) or
           (info.category and info.category:lower():find(query:lower())) then
            
            found = true
            local installed = config.installed[name]
            
            if installed then
                term.setTextColor(colors.green)
                write("[Installé] ")
            else
                term.setTextColor(colors.white)
            end
            
            write(name)
            if info.version then
                write(" (v" .. info.version .. ")")
            end
            print(": " .. (info.description or ""))
            
            if info.category then
                term.setTextColor(colors.gray)
                print("  Catégorie: " .. info.category)
            end
        end
    end
    
    if not found then
        print("Aucun résultat trouvé")
    end
    
    term.setTextColor(colors.white)
end

-- Interface en ligne de commande
local function printUsage()
    print("Usage:")
    print("  cc-pkg install <package>  - Installe un paquet")
    print("  cc-pkg remove <package>   - Désinstalle un paquet")
    print("  cc-pkg list              - Liste tous les paquets")
    print("  cc-pkg list-installed    - Liste les paquets installés")
    print("  cc-pkg search <query>     - Recherche des paquets")
    print("  cc-pkg info <package>     - Affiche les informations d'un paquet")
end

-- Programme principal
local function main(args)
    ensureDirectories()
    local config = loadConfig()
    
    if #args < 1 then
        printUsage()
        return
    end
    
    local command = args[1]
    table.remove(args, 1)
    
    if command == "install" then
        if #args < 1 then
            print("Spécifiez le nom du paquet à installer")
            return
        end
        local success, err = installPackage(args[1], config)
        if not success and err then
            print("Erreur: " .. err)
        end
        
    elseif command == "remove" or command == "uninstall" then
        if #args < 1 then
            print("Spécifiez le nom du paquet à désinstaller")
            return
        end
        local success, err = uninstallPackage(args[1], config)
        if not success and err then
            print("Erreur: " .. err)
        end
        
    elseif command == "list" then
        listPackages(false)
        
    elseif command == "list-installed" then
        listPackages(true)
        
    elseif command == "search" then
        if #args < 1 then
            print("Spécifiez un terme de recherche")
            return
        end
        searchPackages(args[1])
        
    elseif command == "info" then
        if #args < 1 then
            print("Spécifiez le nom du paquet")
            return
        end
        local packages = fetchPackageList()
        if not packages then
            print("Impossible de récupérer les informations")
            return
        end
        
        local package = packages.packages[args[1]]
        if not package then
            print("Paquet non trouvé")
            return
        end
        
        term.setTextColor(colors.cyan)
        print("=== " .. args[1] .. " ===")
        term.setTextColor(colors.white)
        print("Version: " .. (package.version or "N/A"))
        print("Description: " .. (package.description or ""))
        print("Auteur: " .. (package.author or "N/A"))
        print("Catégorie: " .. (package.category or "N/A"))
        
        if package.dependencies and #package.dependencies > 0 then
            print("Dépendances: " .. table.concat(package.dependencies, ", "))
        end
        
        if package.compatibility then
            print("\nCompatibilité:")
            if package.compatibility.requires then
                for k, v in pairs(package.compatibility.requires) do
                    print("  " .. k .. ": " .. tostring(v))
                end
            end
        end
        
    else
        print("Commande inconnue")
        printUsage()
    end
end

-- Lancer le programme
local args = {...}
main(args) 
