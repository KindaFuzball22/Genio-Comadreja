$code = @'
import streamlit as st
import pandas as pd
import json
import os
import io
import textwrap
import base64
from PIL import Image, ImageDraw, ImageFont
from supabase import create_client, Client

st.set_page_config(page_title="Gestor de Horarios Escolares", page_icon="📅", layout="wide")

# Centrar el texto del botón "➕" dentro de su barra (expander)
st.markdown(
    """
    <style>
    div[data-testid="stExpander"] summary {
        justify-content: center;
    }
    div[data-testid="stExpander"] summary p {
        text-align: center;
    }
    /* Celulares: la tabla de edición se ve igual que en PC y se desliza hacia los lados */
    @media (max-width: 640px) {
        .st-key-grilla_horario,
        .st-key-grilla_contraturno {
            overflow-x: auto;
            -webkit-overflow-scrolling: touch;
            padding-bottom: 0.5rem;
            gap: 0.35rem !important;
        }
        .st-key-grilla_horario [data-testid="stHorizontalBlock"],
        .st-key-grilla_contraturno [data-testid="stHorizontalBlock"] {
            flex-wrap: nowrap !important;
            min-width: 700px;
            gap: 0.25rem !important;
        }
        .st-key-grilla_horario [data-testid="stColumn"],
        .st-key-grilla_horario [data-testid="column"],
        .st-key-grilla_contraturno [data-testid="stColumn"],
        .st-key-grilla_contraturno [data-testid="column"] {
            flex: 1 1 110px !important;
            width: auto !important;
            min-width: 0 !important;
        }
        .st-key-grilla_horario [data-testid="stColumn"]:first-child,
        .st-key-grilla_horario [data-testid="column"]:first-child,
        .st-key-grilla_contraturno [data-testid="stColumn"]:first-child,
        .st-key-grilla_contraturno [data-testid="column"]:first-child {
            flex: 0 0 64px !important;
        }
        .st-key-grilla_horario [data-testid="stColumn"] [data-testid="stVerticalBlock"],
        .st-key-grilla_contraturno [data-testid="stColumn"] [data-testid="stVerticalBlock"] {
            gap: 0.25rem !important;
        }
        .st-key-grilla_horario input,
        .st-key-grilla_contraturno input {
            font-size: 12px !important;
            padding: 2px 6px !important;
        }
        .st-key-grilla_horario [data-baseweb="input"],
        .st-key-grilla_contraturno [data-baseweb="input"],
        .st-key-grilla_horario [data-baseweb="base-input"],
        .st-key-grilla_contraturno [data-baseweb="base-input"] {
            min-height: 28px !important;
            height: 28px !important;
        }
        .st-key-grilla_horario p,
        .st-key-grilla_contraturno p {
            font-size: 12px !important;
        }
    }
    </style>
    """,
    unsafe_allow_html=True,
)

# ==========================================
# MÚSICA (carpeta "musica" junto a app.py)
# ==========================================
EXTENSIONES_AUDIO = (".mp3", ".wav", ".ogg", ".m4a")

def carpeta_musica():
    """Busca la carpeta 'musica' (sin importar mayúsculas) junto a app.py o en la carpeta de trabajo."""
    base = os.path.dirname(os.path.abspath(__file__))
    for carpeta in (base, os.getcwd()):
        try:
            for nombre in os.listdir(carpeta):
                ruta = os.path.join(carpeta, nombre)
                if nombre.lower() == "musica" and os.path.isdir(ruta):
                    return ruta
        except OSError:
            pass
    return None

def listar_canciones():
    """Canciones ordenadas por nombre de archivo (ej: 01_..., 02_..., 03_...)."""
    carpeta = carpeta_musica()
    if carpeta is None:
        return []
    return sorted(f for f in os.listdir(carpeta) if f.lower().endswith(EXTENSIONES_AUDIO))

if "cancion_idx" not in st.session_state:
    st.session_state["cancion_idx"] = -1  # -1 = silencio

def siguiente_cancion():
    """Silencio -> canción 1 -> canción 2 -> ... -> última -> silencio."""
    n = len(listar_canciones())
    if n == 0:
        return
    idx = st.session_state["cancion_idx"]
    if idx >= n:
        idx = -1
    idx += 1
    st.session_state["cancion_idx"] = idx if idx < n else -1

def boton_musica(key):
    canciones = listar_canciones()
    idx = st.session_state["cancion_idx"]
    sonando = 0 <= idx < len(canciones)
    if not canciones:
        ayuda = "Agrega canciones en la carpeta 'musica'"
    elif sonando:
        ayuda = f"Sonando: {os.path.splitext(canciones[idx])[0]} ({idx + 1}/{len(canciones)})"
    else:
        ayuda = "Reproducir música"
    st.button("🎶" if sonando else "🎵", key=key, on_click=siguiente_cancion, help=ayuda,
              disabled=not canciones, use_container_width=True)

# Contenedor fijo: la canción no se reinicia al pasar del login al programa
contenedor_musica = st.container()
with contenedor_musica:
    _canciones = listar_canciones()
    _idx = st.session_state["cancion_idx"]
    if 0 <= _idx < len(_canciones):
        st.markdown(
            """
            <style>
            /* Barra de reproducción fija abajo del todo (login y programa) */
            audio[data-testid="stAudio"] {
                position: fixed;
                bottom: max(12px, env(safe-area-inset-bottom));
                left: 50%;
                transform: translateX(-50%);
                width: min(calc(100vw - 16px), 640px);
                height: 48px;
                z-index: 999;
                border-radius: 999px;
                box-shadow: 0 2px 12px rgba(0, 0, 0, 0.5);
            }
            /* Para que la barra no tape el contenido al final de la página */
            .block-container {
                padding-bottom: 6rem;
            }
            @media (max-width: 640px) {
                audio[data-testid="stAudio"] {
                    height: 44px;
                }
            }
            </style>
            """,
            unsafe_allow_html=True,
        )
        st.audio(os.path.join(carpeta_musica(), _canciones[_idx]), autoplay=True, loop=True)

# ==========================================
# CONFIGURACIÓN DE SUPABASE Y CREDENCIALES
# ==========================================
SUPABASE_URL = "https://ibcevhvocpblyurbzqbl.supabase.co"
SUPABASE_KEY = "sb_publishable_qOY3jh9OFockRvkcrO9GNw_sWI8vLfx"

@st.cache_resource
def init_supabase():
    return create_client(SUPABASE_URL.strip(), SUPABASE_KEY.strip())

supabase: Client = init_supabase()

CONFIG_FILE = "config.json"

def cargar_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except:
            return {"contrasena": "1234"}
    return {"contrasena": "1234"}

def guardar_config(config):
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(config, f, ensure_ascii=False, indent=4)

if "config" not in st.session_state:
    st.session_state["config"] = cargar_config()

if "autenticado" not in st.session_state:
    st.session_state["autenticado"] = False

def fondo_login_css():
    """Fondo de la pantalla de contraseña (fondo.jpg junto a app.py), adaptado al tamaño de pantalla."""
    ruta = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fondo.jpg")
    if not os.path.exists(ruta):
        return ""
    with open(ruta, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    return f"""
    <style>
    [data-testid="stAppViewContainer"] {{
        background-image: linear-gradient(rgba(0,0,0,0.30), rgba(0,0,0,0.30)), url("data:image/jpeg;base64,{b64}");
        background-size: cover;
        background-position: center bottom;
        background-repeat: no-repeat;
        background-attachment: fixed;
    }}
    [data-testid="stHeader"] {{
        background: transparent;
    }}
    /* Celulares: el fondo fijo no se lleva bien con iOS/Android, se usa uno normal */
    @media (max-width: 640px) {{
        [data-testid="stAppViewContainer"] {{
            background-attachment: scroll;
        }}
    }}
    </style>
    """

if not st.session_state["autenticado"]:
    st.markdown(fondo_login_css(), unsafe_allow_html=True)
    _, col_centro, _ = st.columns([1, 1, 1])
    with col_centro:
        st.markdown("<br><br><br>", unsafe_allow_html=True)
        password_input = st.text_input("Contraseña", type="password", label_visibility="collapsed", placeholder="Contraseña")
        if st.button("Ingresar", type="primary", use_container_width=True):
            if password_input == st.session_state["config"]["contrasena"]:
                st.session_state["autenticado"] = True
                st.rerun()
            else:
                st.error("Contraseña incorrecta.")
        _, c_musica, _ = st.columns([2, 1, 2])
        with c_musica:
            boton_musica("musica_login")
    st.stop()

# ==========================================
# FUNCIONES DE BASE DE DATOS (SUPABASE)
# ==========================================

def cargar_datos_db():
    try:
        response = supabase.table("horarios").select("*").execute()
        horarios_dict = {}
        for row in response.data:
            key = row["titulo"]
            horarios_dict[key] = {
                "titulo": row["titulo"],
                "curso": row["curso"],
                "division": row["division"],
                "horas": row["horas"],
                "dias": row["dias"],
                "materias": row["materias"],
                "profesores": row["profesores"],
                "contraturno": row["contraturno"]
            }
        st.session_state["error_conexion"] = None
        return horarios_dict
    except Exception as e:
        st.session_state["error_conexion"] = str(e)
        return {}

def guardar_horario_db(titulo, datos):
    try:
        payload = {
            "id": titulo,
            "titulo": datos["titulo"],
            "curso": datos["curso"],
            "division": datos["division"],
            "horas": datos["horas"],
            "dias": datos["dias"],
            "materias": datos["materias"],
            "profesores": datos["profesores"],
            "contraturno": datos["contraturno"]
        }
        supabase.table("horarios").upsert(payload).execute()
    except Exception as e:
        st.error(f"Error al guardar en la base de datos: {e}")

def eliminar_horario_db(titulo):
    try:
        supabase.table("horarios").delete().eq("id", titulo).execute()
    except Exception as e:
        st.error(f"Error al eliminar de la base de datos: {e}")

if "error_conexion" not in st.session_state:
    st.session_state["error_conexion"] = None

if "horarios" not in st.session_state:
    st.session_state["horarios"] = cargar_datos_db()

if st.session_state["error_conexion"]:
    st.error(f"Error al conectar con la base de datos: {st.session_state['error_conexion']} (Verifica en Supabase que el proyecto no esté pausado).")
    if st.button("🔄 Reintentar conexión con la base de datos", type="primary"):
        st.cache_resource.clear()
        st.session_state["horarios"] = cargar_datos_db()
        st.rerun()

if "horario_activo" not in st.session_state:
    st.session_state["horario_activo"] = None

# ==========================================
# PARSEO INTELIGENTE DE PROFESORES
# ==========================================

def extraer_profesores_celda(texto_celda):
    """
    Separa por comas y elimina cualquier prefijo antes del signo '='.
    Ejemplo: 'T=Mariano, S=Ruiz' -> ['Mariano', 'Ruiz']
    """
    nombres_limpios = []
    if not texto_celda or not isinstance(texto_celda, str):
        return nombres_limpios
    
    partes = texto_celda.split(",")
    for parte in partes:
        parte_limpia = parte.strip()
        if "=" in parte_limpia:
            parte_limpia = parte_limpia.split("=", 1)[1].strip()
        if parte_limpia:
            nombres_limpios.append(parte_limpia)
    return nombres_limpios

# ==========================================
# GENERACIÓN DE IMAGEN CON AUTO-AJUSTE DE TEXTO
# ==========================================

def obtener_fuente(size, bold=False):
    rutas = [
        "arialbd.ttf" if bold else "arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
    ]
    for ruta in rutas:
        try:
            return ImageFont.truetype(ruta, size)
        except:
            continue
    return ImageFont.load_default()

def dibujar_texto_ajustado(draw, texto, x, y, ancho_caja, alto_caja, max_size=12, min_size=7, bold=False, color=(0, 0, 0)):
    texto = str(texto).strip()
    if not texto:
        return

    margen_x = 8
    ancho_util = ancho_caja - margen_x

    for size in range(max_size, min_size - 1, -1):
        font = obtener_fuente(size, bold=bold)
        bbox = draw.textbbox((0, 0), texto, font=font)
        w = bbox[2] - bbox[0]
        h = bbox[3] - bbox[1]
        if w <= ancho_util:
            pos_x = x + (ancho_caja - w) // 2
            pos_y = y + (alto_caja - h) // 2 - 1
            draw.text((pos_x, pos_y), texto, fill=color, font=font)
            return

    font = obtener_fuente(min_size, bold=bold)
    mitad = len(texto) // 2
    espacio_izq = texto.rfind(" ", 0, mitad + 4)
    espacio_der = texto.find(" ", mitad)
    
    if espacio_izq != -1 and (espacio_der == -1 or (mitad - espacio_izq) <= (espacio_der - mitad)):
        lineas = [texto[:espacio_izq].strip(), texto[espacio_izq+1:].strip()]
    elif espacio_der != -1:
        lineas = [texto[:espacio_der].strip(), texto[espacio_der+1:].strip()]
    else:
        lineas = textwrap.wrap(texto, width=max(10, int(ancho_util / (min_size * 0.55))))[:2]

    alturas = []
    anchos = []
    for linea in lineas:
        bbox = draw.textbbox((0, 0), linea, font=font)
        anchos.append(bbox[2] - bbox[0])
        alturas.append(bbox[3] - bbox[1])

    espacio_entre_lineas = 2
    alto_total_texto = sum(alturas) + espacio_entre_lineas
    cursor_y = y + (alto_caja - alto_total_texto) // 2

    for idx, linea in enumerate(lineas):
        pos_x = x + (ancho_caja - anchos[idx]) // 2
        draw.text((pos_x, cursor_y), linea, fill=color, font=font)
        cursor_y += alturas[idx] + espacio_entre_lineas

def generar_imagen_horario(nombre_horario, datos):
    num_filas_total = len(datos["horas"])
    if datos.get("contraturno") and "horas" in datos["contraturno"]:
        num_filas_total += len(datos["contraturno"]["horas"])
        
    img_width = 1100
    img_height = max(700, 160 + (num_filas_total * 50))
    
    image = Image.new('RGB', (img_width, img_height), color=(255, 255, 255))
    draw = ImageDraw.Draw(image)

    draw.rectangle([20, 20, img_width - 20, 75], fill=(211, 211, 211), outline=(0, 0, 0))
    titulo_texto = datos.get("titulo", nombre_horario)
    dibujar_texto_ajustado(draw, titulo_texto, 20, 20, img_width - 40, 55, max_size=24, min_size=14, bold=True)
    
    dias = datos["dias"]
    ancho_total_disponible = img_width - 40
    ancho_hora = int(ancho_total_disponible / (len(dias) + 0.5))
    ancho_dia = int((ancho_total_disponible - ancho_hora) / len(dias))
    
    x_cursor = 20
    draw.rectangle([x_cursor, 85, x_cursor + ancho_hora, 120], fill=(255, 255, 0), outline=(0, 0, 0))
    dibujar_texto_ajustado(draw, "HORARIO", x_cursor, 85, ancho_hora, 35, max_size=14, min_size=10, bold=True)
    x_cursor += ancho_hora

    for dia in dias:
        draw.rectangle([x_cursor, 85, x_cursor + ancho_dia, 120], fill=(255, 255, 0), outline=(0, 0, 0))
        dibujar_texto_ajustado(draw, dia, x_cursor, 85, ancho_dia, 35, max_size=14, min_size=10, bold=True)
        x_cursor += ancho_dia

    y_offset = 125
    
    def dibujar_fila(hora_val, materias_row, profs_row, color_hora, color_mat):
        nonlocal y_offset
        x_c = 20
        draw.rectangle([x_c, y_offset, x_c + ancho_hora, y_offset + 45], fill=color_hora, outline=(0, 0, 0))
        dibujar_texto_ajustado(draw, hora_val, x_c, y_offset, ancho_hora, 45, max_size=12, min_size=8, bold=True)
        x_c += ancho_hora

        for col_idx in range(5):
            mat = materias_row[col_idx]
            prof = profs_row[col_idx]
            
            draw.rectangle([x_c, y_offset, x_c + ancho_dia, y_offset + 45], outline=(0, 0, 0))
            
            draw.rectangle([x_c, y_offset, x_c + ancho_dia, y_offset + 22], fill=color_mat, outline=(0, 0, 0))
            dibujar_texto_ajustado(draw, mat, x_c, y_offset, ancho_dia, 22, max_size=12, min_size=7, bold=True)
            
            draw.rectangle([x_c, y_offset + 22, x_c + ancho_dia, y_offset + 45], fill=(255, 255, 255), outline=(0, 0, 0))
            dibujar_texto_ajustado(draw, prof, x_c, y_offset + 22, ancho_dia, 23, max_size=11, min_size=7, bold=False)
            
            x_c += ancho_dia
        y_offset += 45

    for row_idx in range(len(datos["horas"])):
        dibujar_fila(datos["horas"][row_idx], datos["materias"][row_idx], datos["profesores"][row_idx], (255, 165, 0), (173, 216, 230))

    if datos.get("contraturno"):
        ct = datos["contraturno"]
        for row_idx in range(len(ct["horas"])):
            dibujar_fila(ct["horas"][row_idx], ct["materias"][row_idx], ct["profesores"][row_idx], (221, 160, 221), (238, 232, 170))

    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()

col_tit, col_mus, col_btn = st.columns([5, 0.6, 1.4])
with col_tit:
    st.title("Genio Comadreja")
with col_mus:
    st.markdown("<br>", unsafe_allow_html=True)
    boton_musica("musica_app")
with col_btn:
    st.markdown("<br>", unsafe_allow_html=True)
    if st.button("🔑 Cambiar Contraseña", use_container_width=True):
        st.session_state["cambiando_pass"] = True

if not listar_canciones():
    _carpeta = carpeta_musica()
    if _carpeta is None:
        st.caption(f"🎵 No encuentro la carpeta 'musica'. Busqué junto a app.py en: {os.path.dirname(os.path.abspath(__file__))}")
    else:
        st.caption(f"🎵 La carpeta 'musica' no tiene audios válidos (mp3, wav, ogg, m4a). Contiene: {sorted(os.listdir(_carpeta))}")

if st.session_state.get("cambiando_pass", False):
    with st.expander("🔒 Panel de Cambio de Contraseña", expanded=True):
        pass_actual = st.text_input("Contraseña Actual", type="password")
        pass_nueva = st.text_input("Nueva Contraseña", type="password")
        pass_nueva_conf = st.text_input("Confirmar Nueva Contraseña", type="password")
        
        c_p1, c_p2 = st.columns(2)
        with c_p1:
            if st.button("Guardar Nueva Contraseña", type="primary"):
                if pass_actual == st.session_state["config"]["contrasena"]:
                    if pass_nueva and pass_nueva == pass_nueva_conf:
                        st.session_state["config"]["contrasena"] = pass_nueva
                        guardar_config(st.session_state["config"])
                        st.session_state["cambiando_pass"] = False
                        st.success("¡Contraseña actualizada con éxito!")
                        st.rerun()
                    else:
                        st.error("Las nuevas contraseñas no coinciden o están vacías.")
                else:
                    st.error("La contraseña actual es incorrecta.")
        with c_p2:
            if st.button("Cancelar"):
                st.session_state["cambiando_pass"] = False
                st.rerun()

st.markdown("---")

col_top1, col_top2 = st.columns([1, 4])
with col_top1:
    with st.expander("➕"):
        nuevo_tit = st.text_input("Título del Horario (ej: 6to G 2026)", value="")
        n_curso = st.text_input("Curso (ej: 6)", value="")
        n_div = st.text_input("División (ej: G)", value="")
        if st.button("Guardar Nuevo Horario", type="primary"):
            titulo_limpio = nuevo_tit.strip()
            if titulo_limpio and titulo_limpio not in st.session_state["horarios"]:
                nuevo_datos = {
                    "titulo": titulo_limpio,
                    "curso": n_curso.strip(),
                    "division": n_div.strip(),
                    "horas": ["" for _ in range(9)],
                    "dias": ["LUNES", "MARTES", "MIERCOLES", "JUEVES", "VIERNES"],
                    "materias": [["" for _ in range(5)] for _ in range(9)],
                    "profesores": [["" for _ in range(5)] for _ in range(9)],
                    "contraturno": None
                }
                st.session_state["horarios"][titulo_limpio] = nuevo_datos
                guardar_horario_db(titulo_limpio, nuevo_datos)
                st.session_state["horario_activo"] = titulo_limpio
                st.success(f"¡Horario '{titulo_limpio}' creado y guardado en la nube!")
                st.rerun()
            else:
                st.error("Por favor ingresa un título válido que no esté repetido.")

st.markdown("### Buscar")

profesores_encontrados = set()
for h in st.session_state["horarios"].values():
    for row in h.get("profesores", []):
        for p in row:
            for nombre_indiv in extraer_profesores_celda(p):
                profesores_encontrados.add(nombre_indiv)
    ct = h.get("contraturno")
    if ct and isinstance(ct, dict):
        for row in ct.get("profesores", []):
            for p in row:
                for nombre_indiv in extraer_profesores_celda(p):
                    profesores_encontrados.add(nombre_indiv)

lista_profesores = sorted(list(profesores_encontrados))
lista_cursos = sorted(list({h.get("curso", "").strip() for h in st.session_state["horarios"].values() if h.get("curso", "").strip()}))
lista_divisiones = sorted(list({h.get("division", "").strip() for h in st.session_state["horarios"].values() if h.get("division", "").strip()}))

materias_encontradas = set()
for h in st.session_state["horarios"].values():
    for row in h.get("materias", []):
        for m in row:
            if m and m.strip():
                materias_encontradas.add(m.strip())
    ct = h.get("contraturno")
    if ct and isinstance(ct, dict):
        for row in ct.get("materias", []):
            for m in row:
                if m and m.strip():
                    materias_encontradas.add(m.strip())

lista_materias = sorted(list(materias_encontradas))
lista_titulos_horarios = sorted(list(st.session_state["horarios"].keys()))

col1, col2, col3, col4, col5 = st.columns(5)
with col1:
    search_prof = st.selectbox("Profesor", lista_profesores, index=None, placeholder="Escoge una opcion") or ""
with col2:
    search_curso = st.selectbox("Curso", lista_cursos, index=None, placeholder="Escoge una opcion") or ""
with col3:
    search_div = st.selectbox("División", lista_divisiones, index=None, placeholder="Escoge una opcion") or ""
with col4:
    search_materia = st.selectbox("Materia", lista_materias, index=None, placeholder="Escoge una opcion") or ""
with col5:
    search_directo = st.selectbox("Acceso Directo", lista_titulos_horarios, index=None, placeholder="Escoge una opcion") or ""

if search_directo != "":
    st.session_state["horario_activo"] = search_directo

coincidencias = []
for key, h_data in st.session_state["horarios"].items():
    cumple = True
    if search_curso != "" and h_data.get("curso") != search_curso:
        cumple = False
    if search_div != "" and h_data.get("division") != search_div:
        cumple = False
    
    if search_prof != "":
        objetivo_prof = search_prof.lower()
        prof_en_principal = any(
            objetivo_prof == nombre_indiv.lower()
            for row in h_data.get("profesores", [])
            for p in row
            for nombre_indiv in extraer_profesores_celda(p)
        )
        ct_data = h_data.get("contraturno")
        prof_en_ct = False
        if ct_data and isinstance(ct_data, dict):
            prof_en_ct = any(
                objetivo_prof == nombre_indiv.lower()
                for row in ct_data.get("profesores", [])
                for p in row
                for nombre_indiv in extraer_profesores_celda(p)
            )
        
        if not (prof_en_principal or prof_en_ct):
            cumple = False
            
    if search_materia != "":
        mat_en_principal = any(search_materia.lower() in m.lower() for row in h_data.get("materias", []) for m in row if m)
        ct_data = h_data.get("contraturno")
        mat_en_ct = False
        if ct_data and isinstance(ct_data, dict):
            mat_en_ct = any(search_materia.lower() in m.lower() for row in ct_data.get("materias", []) for m in row if m)
            
        if not (mat_en_principal or mat_en_ct):
            cumple = False
            
    if cumple:
        coincidencias.append(key)

if search_directo == "" and (search_prof != "" or search_curso != "" or search_div != "" or search_materia != ""):
    st.markdown("#### 📋 Resultados de Búsqueda:")
    if coincidencias:
        cols_res = st.columns(min(len(coincidencias), 4))
        for idx, key_match in enumerate(coincidencias):
            with cols_res[idx % 4]:
                if st.button(f"📌 {key_match}", key=f"res_{key_match}", use_container_width=True):
                    st.session_state["horario_activo"] = key_match
                    st.rerun()
    else:
        st.info("No se encontraron horarios con los filtros seleccionados.")

st.markdown("---")

active_key = st.session_state["horario_activo"]

if active_key and active_key in st.session_state["horarios"]:
    datos = st.session_state["horarios"][active_key]
    
    st.subheader(f"✏️ Editando Horario: {datos['titulo']}")
    
    c_t, c_c, c_d = st.columns([3, 1, 1])
    with c_t:
        nuevo_titulo = st.text_input("Título Principal", value=datos["titulo"])
        if nuevo_titulo.strip() and nuevo_titulo.strip() != active_key:
            nuevo_t_limpio = nuevo_titulo.strip()
            if nuevo_t_limpio not in st.session_state["horarios"]:
                eliminar_horario_db(active_key)
                st.session_state["horarios"][nuevo_t_limpio] = st.session_state["horarios"].pop(active_key)
                st.session_state["horarios"][nuevo_t_limpio]["titulo"] = nuevo_t_limpio
                st.session_state["horario_activo"] = nuevo_t_limpio
                guardar_horario_db(nuevo_t_limpio, st.session_state["horarios"][nuevo_t_limpio])
                st.rerun()
    with c_c:
        nuevo_curso = st.text_input("Curso", value=datos["curso"])
        if nuevo_curso != datos["curso"]:
            datos["curso"] = nuevo_curso.strip()
            guardar_horario_db(active_key, datos)
    with c_d:
        nueva_div = st.text_input("División", value=datos["division"])
        if nueva_div != datos["division"]:
            datos["division"] = nueva_div.strip()
            guardar_horario_db(active_key, datos)

    st.markdown("##### Horario principal")
    
    with st.container(key="grilla_horario"):
        cols_grid = st.columns([1.5, 2, 2, 2, 2, 2])
        cols_grid[0].markdown("**HORARIO**")
        for idx, dia in enumerate(datos["dias"]):
            cols_grid[idx + 1].markdown(f"**{dia}**")

        for i in range(9):
            cols_row = st.columns([1.5, 2, 2, 2, 2, 2])
            nueva_hora = cols_row[0].text_input(f"H{i}", value=datos["horas"][i], key=f"h_{active_key}_{i}", placeholder="Hora", label_visibility="collapsed")
            if nueva_hora != datos["horas"][i]:
                datos["horas"][i] = nueva_hora
                guardar_horario_db(active_key, datos)
        
            for j in range(5):
                with cols_row[j + 1]:
                    nueva_mat = cols_row[j + 1].text_input(f"M{i}_{j}", value=datos["materias"][i][j], key=f"m_{active_key}_{i}_{j}", placeholder="Materia", label_visibility="collapsed")
                    nuevo_prof = cols_row[j + 1].text_input(f"P{i}_{j}", value=datos["profesores"][i][j], key=f"p_{active_key}_{i}_{j}", placeholder="Profesor", label_visibility="collapsed")
                
                    if nueva_mat != datos["materias"][i][j]:
                        datos["materias"][i][j] = nueva_mat
                        guardar_horario_db(active_key, datos)
                    if nuevo_prof != datos["profesores"][i][j]:
                        datos["profesores"][i][j] = nuevo_prof
                        guardar_horario_db(active_key, datos)

    st.markdown("---")
    st.markdown("##### 🌙 Sección Contraturno")
    
    with st.container(key="grilla_contraturno"):
        if datos["contraturno"] is not None:
            ct = datos["contraturno"]
            for i in range(len(ct["horas"])):
                cols_ct = st.columns([1.5, 2, 2, 2, 2, 2])
                ct_h_val = cols_ct[0].text_input(f"CT H{i}", value=ct["horas"][i], key=f"ct_h_{active_key}_{i}", placeholder="Hora", label_visibility="collapsed")
                if ct_h_val != ct["horas"][i]:
                    ct["horas"][i] = ct_h_val
                    guardar_horario_db(active_key, datos)
                
                for j in range(5):
                    with cols_ct[j + 1]:
                        ct_m_val = cols_ct[j + 1].text_input(f"CT M{i}_{j}", value=ct["materias"][i][j], key=f"ct_m_{active_key}_{i}_{j}", placeholder="Materia", label_visibility="collapsed")
                        ct_p_val = cols_ct[j + 1].text_input(f"CT P{i}_{j}", value=ct["profesores"][i][j], key=f"ct_p_{active_key}_{i}_{j}", placeholder="Profesor", label_visibility="collapsed")
                    
                        if ct_m_val != ct["materias"][i][j]:
                            ct["materias"][i][j] = ct_m_val
                            guardar_horario_db(active_key, datos)
                        if ct_p_val != ct["profesores"][i][j]:
                            ct["profesores"][i][j] = ct_p_val
                            guardar_horario_db(active_key, datos)

    col_ct_btn1, col_ct_btn2 = st.columns(2)
    with col_ct_btn1:
        if st.button("➕ Agregar 1 Fila de Contraturno", use_container_width=True):
            if datos["contraturno"] is None:
                datos["contraturno"] = {
                    "horas": [""],
                    "materias": [["" for _ in range(5)]],
                    "profesores": [["" for _ in range(5)]]
                }
            else:
                datos["contraturno"]["horas"].append("")
                datos["contraturno"]["materias"].append(["" for _ in range(5)])
                datos["contraturno"]["profesores"].append(["" for _ in range(5)])
            guardar_horario_db(active_key, datos)
            st.rerun()

    with col_ct_btn2:
        if datos["contraturno"] is not None and len(datos["contraturno"]["horas"]) > 0:
            if st.button("➖ Eliminar Última Fila de Contraturno", use_container_width=True):
                datos["contraturno"]["horas"].pop()
                datos["contraturno"]["materias"].pop()
                datos["contraturno"]["profesores"].pop()
                if len(datos["contraturno"]["horas"]) == 0:
                    datos["contraturno"] = None
                guardar_horario_db(active_key, datos)
                st.rerun()

    st.markdown("---")
    
    col_del1, col_del2 = st.columns([4, 1])
    with col_del2:
        if st.button("🗑️ Eliminar Horario", type="secondary"):
            eliminar_horario_db(active_key)
            del st.session_state["horarios"][active_key]
            st.session_state["horario_activo"] = None
            st.success("¡Horario eliminado correctamente de la nube!")
            st.rerun()

    img_bytes = generar_imagen_horario(active_key, datos)
    st.download_button(
        label="📷 Descargar / Compartir Imagen No Modificable",
        data=img_bytes,
        file_name=f"{datos['titulo']}_Horario.png",
        mime="image/png",
        type="primary",
        use_container_width=True
    )
else:
    st.info("👈 Crea un nuevo horario usando el botón de arriba o selecciónalo desde el Acceso Directo para comenzar.")
'@
Set-Content -Path app.py -Value $code -Encoding UTF8
