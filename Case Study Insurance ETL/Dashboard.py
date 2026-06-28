import streamlit as st
import pandas as pd
import pyodbc
import plotly.graph_objects as go
import plotly.express as px
from plotly.subplots import make_subplots

# =============================================================================
# 1. PAGE CONFIG
# =============================================================================
st.set_page_config(
    page_title="ETL Command Center",
    page_icon="⚙️",
    layout="wide",
    initial_sidebar_state="collapsed"
)

# =============================================================================
# 2. TABLEAU / POWER BI STYLE CSS
# =============================================================================
st.markdown("""
<style>
/* 1. Set the entire dashboard background to a soft BI-style gray */
[data-testid="stAppViewContainer"] {
    background-color: #F1F5F9; 
}

/* 2. Tighten the main canvas padding */
.block-container {
    padding-top: 1.5rem !important;
    padding-bottom: 1.5rem !important;
    padding-left: 2rem !important;
    padding-right: 2rem !important;
    max-width: 100% !important;
}

/* 3. Style the KPI Cards to look like solid white BI tiles */
div[data-testid="stMetric"] {
    background-color: #FFFFFF;
    border: 1px solid #E2E8F0;
    border-radius: 8px;
    padding: 15px 20px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.05);
}
div[data-testid="stMetricValue"] {
    font-size: 26px !important;
    font-weight: 700 !important;
    color: #0F172A !important;
}
div[data-testid="stMetricLabel"] {
    font-size: 13px !important;
    font-weight: 600 !important;
    color: #64748B !important;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}

/* 4. Online Status Pill */
.status-pill {
    background-color: #DCFCE7;
    color: #166534;
    padding: 6px 14px;
    border-radius: 12px;
    font-size: 12px;
    font-weight: 700;
    border: 1px solid #BBF7D0;
}
</style>
""", unsafe_allow_html=True)

# =============================================================================
# 3. HEADER ARCHITECTURE
# =============================================================================
title_col, status_col = st.columns([6, 1])

with title_col:
    st.markdown("<h2 style='margin-bottom: 0px; color: #0F172A;'>ETL Quality Command Center</h2>", unsafe_allow_html=True)
    st.markdown("<p style='color: #64748B; font-size: 14px; margin-top: -5px;'>Enterprise real-time health monitoring and automated quarantine auditing</p>", unsafe_allow_html=True)

with status_col:
    st.markdown('<div style="text-align:right; padding-top: 10px;"><span class="status-pill">● SYSTEM ONLINE</span></div>', unsafe_allow_html=True)

st.markdown("<div style='margin-bottom: 20px;'></div>", unsafe_allow_html=True)

# =============================================================================
# 4. DATABASE ACQUISITION LAYER
# =============================================================================
@st.cache_data(ttl=15)
def fetch_pipeline_data():
    conn_str = (
        r"DRIVER={ODBC Driver 17 for SQL Server};"
        r"SERVER=KROCKZI\SQLEXPRESS;"
        r"DATABASE=Insurance_ETL_CaseStudy;"
        r"Trusted_Connection=yes;"
    )
    conn = pyodbc.connect(conn_str)
    
    timeline_query = """
    WITH SuccessTimeline AS (
        SELECT CAST(LOAD_TS AS DATE) as LogDate, COUNT(*) as RowsLoaded
        FROM dbo.ILM_POLICY WHERE LOAD_TS IS NOT NULL GROUP BY CAST(LOAD_TS AS DATE)
    ),
    ErrorTimeline AS (
        SELECT CAST(GETDATE() AS DATE) as LogDate, COUNT(*) as TotalErrors
        FROM dbo.ERROR_POLICY
    ),
    AllDates AS (
        SELECT LogDate FROM SuccessTimeline UNION SELECT LogDate FROM ErrorTimeline
    )
    SELECT 
        d.LogDate,
        COALESCE(s.RowsLoaded, 0) as RowsLoaded,
        COALESCE(e.TotalErrors, 0) as TotalErrors,
        CASE 
            WHEN (COALESCE(s.RowsLoaded, 0) + COALESCE(e.TotalErrors, 0)) > 0 
            THEN CAST(COALESCE(s.RowsLoaded, 0) AS FLOAT) / (COALESCE(s.RowsLoaded, 0) + COALESCE(e.TotalErrors, 0))
            ELSE 1.0
        END as YieldRate
    FROM AllDates d
    LEFT JOIN SuccessTimeline s ON d.LogDate = s.LogDate
    LEFT JOIN ErrorTimeline e ON d.LogDate = e.LogDate;
    """
    
    error_profile_query = """SELECT REJECT_REASON, COUNT(*) as ErrorCount FROM dbo.ERROR_POLICY GROUP BY REJECT_REASON;"""
    quarantine_query = """SELECT POL_NBR, EFF_DT, ST_CD, LOB_CD, REJECT_REASON, SRC_UPDATE_TS FROM dbo.ERROR_POLICY;"""
    
    df_time = pd.read_sql(timeline_query, conn)
    df_err = pd.read_sql(error_profile_query, conn)
    df_quar = pd.read_sql(quarantine_query, conn)
    conn.close()
    
    if not df_time.empty:
        df_time['LogDate'] = df_time['LogDate'].astype(str)
        df_time = df_time.sort_values('LogDate')
        
    return df_time, df_err, df_quar

try:
    df_time, df_err, df_quar = fetch_pipeline_data()
except Exception as database_exception:
    st.error(f"Database Connectivity Failure: {database_exception}")
    st.stop()

# =============================================================================
# 5. KPI SCORECARD (Top Row)
# =============================================================================
total_success = int(df_time['RowsLoaded'].sum()) if not df_time.empty else 0
total_errors = int(df_time['TotalErrors'].sum()) if not df_time.empty else 0
total_processed = total_success + total_errors
global_yield = (total_success / total_processed) * 100 if total_processed > 0 else 0.0

kpi1, kpi2, kpi3, kpi4 = st.columns(4)
with kpi1:
    st.metric("Records Evaluated", f"{total_processed:,}")
with kpi2:
    st.metric("Target Loads", f"{total_success:,}")
with kpi3:
    status_indicator = "🟢" if global_yield >= 95 else "🟡" if global_yield >= 85 else "🔴"
    st.metric("Quality Yield SLA", f"{global_yield:.2f}% {status_indicator}")
with kpi4:
    st.metric("Total Errors", f"{total_errors:,}")

st.markdown("<div style='margin-bottom: 20px;'></div>", unsafe_allow_html=True)

# =============================================================================
# 6. MIDDLE GRID: TIMELINE & PIE CHART
# =============================================================================
col_timeline, col_pie = st.columns([6, 4])

with col_timeline:
    # Wrapping inside a bordered container creates the "BI Card" look
    with st.container(border=True):
        st.markdown("<h4 style='font-size: 15px; color: #334155; margin-bottom: 0px;'>Ingestion Velocity vs. Quality Trend</h4>", unsafe_allow_html=True)
        
        fig_timeline = make_subplots(specs=[[{"secondary_y": True}]])
        fig_timeline.add_trace(
            go.Bar(x=df_time['LogDate'], y=df_time['RowsLoaded'], name="Rows Loaded", marker_color='#3B82F6', opacity=0.85), secondary_y=False
        )
        fig_timeline.add_trace(
            go.Scatter(x=df_time['LogDate'], y=df_time['YieldRate'] * 100, name="Yield SLA %", line=dict(color='#EF4444', width=3), mode='lines+markers'), secondary_y=True
        )
        
        # Reduced height to 280 to stop it from looking "too huge"
        fig_timeline.update_layout(
            plot_bgcolor='white', paper_bgcolor='white',
            bargap=0.7 if len(df_time) == 1 else 0.2, # Keeps single bar thin
            xaxis=dict(title="", type="category", showgrid=False),
            yaxis=dict(title="Volume", showgrid=True, gridcolor='#F1F5F9'),
            yaxis2=dict(title="Yield (%)", ticksuffix="%", range=[0, 105], showgrid=False, overlaying="y", side="right"),
            legend=dict(orientation="h", yanchor="bottom", y=1.05, xanchor="right", x=1),
            margin=dict(l=0, r=0, t=20, b=0),
            height=280
        )
        st.plotly_chart(fig_timeline, use_container_width=True)

with col_pie:
    with st.container(border=True):
        st.markdown("<h4 style='font-size: 15px; color: #334155; margin-bottom: 0px;'>Defect Proportion</h4>", unsafe_allow_html=True)
        if not df_err.empty:
            fig_pie = px.pie(
                df_err, values='ErrorCount', names='REJECT_REASON', hole=0.5,
                color_discrete_sequence=['#F59E0B', '#10B981', '#3B82F6', '#6366F1', '#EC4899']
            )
            fig_pie.update_layout(
                plot_bgcolor='white', paper_bgcolor='white',
                margin=dict(l=0, r=0, t=20, b=0), height=280,
                legend=dict(orientation="h", yanchor="bottom", y=-0.2, xanchor="center", x=0.5)
            )
            st.plotly_chart(fig_pie, use_container_width=True)
        else:
            st.info("No defects logged.")

# =============================================================================
# 7. BOTTOM GRID: BAR CHART & QUARANTINE LOGS
# =============================================================================
col_bar, col_table = st.columns([3, 7])

with col_bar:
    with st.container(border=True):
        st.markdown("<h4 style='font-size: 15px; color: #334155; margin-bottom: 0px;'>Top Defects</h4>", unsafe_allow_html=True)
        if not df_err.empty:
            df_err_sorted = df_err.sort_values(by='ErrorCount', ascending=True)
            fig_bar = px.bar(
                df_err_sorted, x='ErrorCount', y='REJECT_REASON', orientation='h',
                text='ErrorCount', color_discrete_sequence=['#312E81']
            )
            fig_bar.update_traces(textposition='outside')
            fig_bar.update_layout(
                plot_bgcolor='white', paper_bgcolor='white',
                xaxis=dict(title="Count", showgrid=True, gridcolor='#F1F5F9'),
                yaxis=dict(title="", showgrid=False),
                margin=dict(l=0, r=20, t=20, b=0), height=300
            )
            st.plotly_chart(fig_bar, use_container_width=True)
        else:
            st.info("No defects logged.")

with col_table:
    with st.container(border=True):
        st.markdown("<h4 style='font-size: 15px; color: #334155; margin-bottom: 15px;'>Quarantine Logs</h4>", unsafe_allow_html=True)
        
        if not df_quar.empty:
            search_col, reason_col = st.columns([1, 1])
            with search_col:
                search_term = st.text_input("Search ID:", placeholder="Enter Policy NBR...", label_visibility="collapsed")
            with reason_col:
                distinct_reasons = ["ALL"] + list(df_quar['REJECT_REASON'].unique())
                selected_reason = st.selectbox("Filter:", distinct_reasons, label_visibility="collapsed")
            
            filtered_df = df_quar.copy()
            if search_term:
                filtered_df = filtered_df[filtered_df['POL_NBR'].astype(str).str.contains(search_term, case=False, na=False)]
            if selected_reason != "ALL":
                filtered_df = filtered_df[filtered_df['REJECT_REASON'] == selected_reason]
            
            st.dataframe(
                filtered_df,
                column_config={
                    "POL_NBR": st.column_config.TextColumn("Policy ID"),
                    "EFF_DT": st.column_config.TextColumn("Source Date"),
                    "ST_CD": st.column_config.TextColumn("State"),
                    "LOB_CD": st.column_config.TextColumn("LOB"),
                    "REJECT_REASON": st.column_config.TextColumn("Defect Reason"),
                    "SRC_UPDATE_TS": st.column_config.DatetimeColumn("Execution Time")
                },
                use_container_width=True, hide_index=True, height=205 # Constrained table height
            )
        else:
            st.success("✅ Quarantine table is empty.")