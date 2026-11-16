import streamlit as st
import pandas as pd
import json
import os
import io
import textwrap
from PIL import Image, ImageDraw, ImageFont
from supabase import create_client, Client

st.set_page_config(page_title="Gestor de Horarios Escolares", page_icon="📅", layout="wide")

# ==========================================
# CONFIGURACIÓN DE SUPABASE Y CREDENCIALES
# ==========================================
SUPABASE_URL = "https://ibcevhvocpblyurbzqbl.supabase.co"
SUPABASE_KEY = "sb_publishable_qOY3jh9OFockRvkcrO9GNw_sWI8vLfx"

@st.cache_resource
def init_supabase():
    return create_client(SUPABASE_URL, SUPABASE_KEY)

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

if not st.session_state["autenticado"]:
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
        return horarios_dict
    except Exception as e:
        st.error(f"Error al conectar con la base de datos: {e}")
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

if "horarios" not in st.session_state:
    st.session_state["horarios"] = cargar_datos_db()

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

col_tit, col_btn = st.columns([5, 1])
with col_tit:
    st.title("🏫 Gestor Centralizado de Horarios Escolares")
with col_btn:
    st.markdown("<br>", unsafe_allow_html=True)
    if st.button("🔑 Cambiar Contraseña", use_container_width=True):
        st.session_state["cambiando_pass"] = True

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
    with st.expander("➕ Crear Nuevo Horario"):
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

st.markdown("### 🔍 Panel de Búsqueda Combinada")

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
    search_prof = st.selectbox("Profesor", [""] + lista_profesores)
with col2:
    search_curso = st.selectbox("Curso", [""] + lista_cursos)
with col3:
    search_div = st.selectbox("División", [""] + lista_divisiones)
with col4:
    search_materia = st.selectbox("Materia", [""] + lista_materias)
with col5:
    search_directo = st.selectbox("Acceso Directo", [""] + lista_titulos_horarios)

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

    st.markdown("##### 📅 Grilla Principal (9 Horas)")
    
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

    st.success("💾 Todos los cambios se guardan automáticamente en la base de datos.")

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
