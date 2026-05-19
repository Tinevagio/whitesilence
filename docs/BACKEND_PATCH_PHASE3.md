# Patch backend — Servir Front End V7.html à la racine

## Objectif

Que `https://snow-conditions.onrender.com/` renvoie directement le `Front End V7.html` (au lieu d'un 404 ou de la doc FastAPI auto-générée).

## Modifications à apporter à `api/main.py`

### 1. Ajouter l'import en haut du fichier

Près des autres imports FastAPI (vers la ligne 27), ajoute :

```python
from fastapi.responses import FileResponse
import os as _os
```

### 2. Ajouter la route GET / juste APRÈS le bloc `app.add_middleware(...)` (donc vers la ligne 131)

```python
# ---------------------------------------------------------------------------
# Front-end HTML — servi pour intégration mobile WhiteSilence + accès web direct
# ---------------------------------------------------------------------------

_FRONTEND_HTML_PATH = _os.path.join(
    _os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
    "Front End V7.html",
)

@app.get("/", include_in_schema=False)
def serve_frontend():
    """Sert le frontend HTML à la racine pour les WebView mobiles."""
    if _os.path.exists(_FRONTEND_HTML_PATH):
        return FileResponse(_FRONTEND_HTML_PATH, media_type="text/html")
    # Fallback : redirige vers la doc Swagger si le HTML n'est pas trouvé
    return {"detail": "Frontend HTML not found", "docs": "/docs"}
```

### 3. (Optionnel) Renommer le fichier pour éviter les espaces

`Front End V7.html` avec espaces et majuscules est correct mais fragile sur certains
filesystems. Je recommande de le renommer en `frontend.html` à la racine, et de
changer le `_FRONTEND_HTML_PATH` en conséquence. Ce n'est PAS bloquant pour le
patch ci-dessus qui marche tel quel.

## Test du patch

Une fois déployé sur Render (push sur main, attendre que Render rebuild) :

```bash
curl -I https://snow-conditions.onrender.com/
# Devrait retourner : HTTP/1.1 200 OK + Content-Type: text/html
```

Ou directement dans Chrome : ouvre l'URL, tu dois voir ton interface V7.

## Notes

- `include_in_schema=False` évite que la route `/` pollue la doc Swagger
- `FileResponse` envoie le fichier sans le charger en mémoire (efficient pour 75 KB)
- Tous les endpoints `/conditions`, `/avalanche`, etc. continuent de fonctionner
  tels quels — on ne touche pas à la logique métier
- Le CORS reste ouvert (`allow_origins=["*"]`), ce qui est nécessaire pour que
  le HTML appelle ses propres endpoints depuis une WebView mobile
