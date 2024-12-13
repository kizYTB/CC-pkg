<div align = "center">
  <img src = "https://www.jtheberg.cloud/assets/img/logo.png" />
  <h1>CC-pkg</h1>
  <h2>Powered by Kiz___ of <a href="https://jtheberg.cloud">Jtheberg</a></h2>
  <p>A package manager for CC Tweaked</p>
</div>
<br />
<br />

# Installation
To install the package manager run these commands
```
cd /
wget https://raw.githubusercontent.com/kizYTB/CC-pkg/refs/heads/main/lib-pkg.lua pkg.lua
```

# Commands list

To install a program execute this command

```
pkg install "PACKAGE"
```
To listen package you can install execute this command

```
pkg list
```

# All packages

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Afficher le JSON</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
        }
        pre {
            background: #f4f4f4;
            padding: 10px;
            border-radius: 5px;
        }
    </style>
</head>
<body>
    <h1>Contenu du JSON</h1>
    <div id="json-content">
        <p>Chargement des données...</p>
    </div>

    <script>
        // Lien brut vers le fichier JSON dans votre repo GitHub
        const jsonPath = 'https://raw.githubusercontent.com/<votre-utilisateur>/<votre-repo>/main/data.json';

        // Fonction pour charger et afficher le JSON
        fetch(jsonPath)
            .then(response => {
                if (!response.ok) {
                    throw new Error('Erreur lors du chargement du fichier JSON.');
                }
                return response.json();
            })
            .then(data => {
                const container = document.getElementById('json-content');
                container.innerHTML = ''; // Réinitialiser le contenu

                // Filtrer et afficher le JSON sans les clés "install"
                const filteredData = Object.entries(data).filter(([key]) => key !== 'install');

                // Générer un affichage lisible
                filteredData.forEach(([key, value]) => {
                    const item = document.createElement('div');
                    item.innerHTML = `<strong>${key}:</strong> ${JSON.stringify(value, null, 2)}`;
                    container.appendChild(item);
                });
            })
            .catch(error => {
                document.getElementById('json-content').textContent = `Erreur: ${error.message}`;
            });
    </script>
</body>
</html>
