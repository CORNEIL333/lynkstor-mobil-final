document.addEventListener('DOMContentLoaded', () => {
  const STORAGE_KEY = 'lynkstor_admin_token';
  const API_BASE_KEY = 'lynkstor_api_base';
  let salesChart = null;
  let map = null;
  let mapMarkers = [];

  /**
   * Base URL de l’API Node.
   * - Monolithe (Render/Docker) : vide → mêmes origines (/api/...)
   * - Admin statique (Cloudflare) : URL complète du backend, ex. https://api.example.com
   */
  function getApiBase() {
    const stored = (localStorage.getItem(API_BASE_KEY) || '').replace(/\/$/, '');
    if (stored) return stored;
    if (typeof window.LYNKSTOR_API_BASE === 'string' && window.LYNKSTOR_API_BASE) {
      return window.LYNKSTOR_API_BASE.replace(/\/$/, '');
    }
    if (
      window.LYNKSTOR_CONFIG &&
      typeof window.LYNKSTOR_CONFIG.apiBase === 'string' &&
      window.LYNKSTOR_CONFIG.apiBase
    ) {
      return window.LYNKSTOR_CONFIG.apiBase.replace(/\/$/, '');
    }
    return '';
  }

  function apiUrl(path) {
    const p = path.startsWith('/') ? path : `/${path}`;
    return `${getApiBase()}${p}`;
  }

  // ——— Auth ———
  function getToken() {
    return sessionStorage.getItem(STORAGE_KEY) || '';
  }

  function setToken(token) {
    if (token) sessionStorage.setItem(STORAGE_KEY, token);
    else sessionStorage.removeItem(STORAGE_KEY);
  }

  function getSupabaseAnonKey() {
    if (
      window.LYNKSTOR_CONFIG &&
      typeof window.LYNKSTOR_CONFIG.supabaseAnonKey === 'string' &&
      window.LYNKSTOR_CONFIG.supabaseAnonKey
    ) {
      return window.LYNKSTOR_CONFIG.supabaseAnonKey;
    }
    return '';
  }

  function authHeaders(extra = {}) {
    const token = getToken();
    const anon = getSupabaseAnonKey();
    // Supabase gateway : header apikey (publishable) + Authorization applicatif
    const headers = {
      'Content-Type': 'application/json',
      ...extra,
    };
    if (anon) headers.apikey = anon;
    if (token) headers.Authorization = `Bearer ${token}`;
    else if (anon) headers.Authorization = `Bearer ${anon}`;
    return headers;
  }

  function showLoginGate(message) {
    const gate = document.getElementById('login-gate');
    if (gate) {
      gate.classList.add('active');
      gate.setAttribute('aria-hidden', 'false');
    }
    const err = document.getElementById('login-error');
    if (err) {
      err.textContent = message || '';
      err.style.display = message ? 'block' : 'none';
    }
  }

  function hideLoginGate() {
    const gate = document.getElementById('login-gate');
    if (gate) {
      // Ne pas laisser le focus dans un élément qu'on marque aria-hidden (a11y).
      if (gate.contains(document.activeElement) && document.activeElement.blur) {
        document.activeElement.blur();
      }
      gate.classList.remove('active');
      gate.setAttribute('aria-hidden', 'true');
    }
  }

  async function api(url, options = {}) {
    const target = url.startsWith('http') ? url : apiUrl(url);
    const res = await fetch(target, {
      ...options,
      headers: { ...authHeaders(), ...(options.headers || {}) },
    });

    if (res.status === 401) {
      showLoginGate('Session expirée ou clé API invalide. Connectez-vous.');
      throw new Error('UNAUTHORIZED');
    }
    if (res.status === 403) {
      const payload = await res.clone().json().catch(() => ({}));
      alert(payload.message || 'Votre rôle ne permet pas cette action.');
      throw new Error('FORBIDDEN');
    }

    return res;
  }

  // Le gateway Neon répond {status:'ok', data}, l'ancien Express {status:'success', data}.
  function isOk(json) {
    return !!json && (json.status === 'success' || json.status === 'ok');
  }

  // Login form
  const loginForm = document.getElementById('login-form');
  if (loginForm) {
    loginForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const username = document.getElementById('login-user').value.trim();
      const password = document.getElementById('login-pass').value;
      const tokenManual = document.getElementById('login-token').value.trim();
      const apiBaseInput = document.getElementById('login-api-base');
      if (apiBaseInput && apiBaseInput.value.trim()) {
        localStorage.setItem(API_BASE_KEY, apiBaseInput.value.trim().replace(/\/$/, ''));
      }

      try {
        if (tokenManual) {
          setToken(tokenManual);
          hideLoginGate();
          await bootstrap();
          return;
        }

        const res = await fetch(apiUrl('/api/v1/auth/login'), {
          method: 'POST',
          headers: authHeaders(),
          body: JSON.stringify({ username, password }),
        });
        const json = await res.json();
        const ld = json.data || json; // gateway Neon: {status:'ok', data:{token, role}}
        if (res.ok && ld.token) {
          setToken(ld.token);
          sessionStorage.setItem('lynkstor_user_role', ld.role || 'super_admin');
          sessionStorage.setItem('lynkstor_user_name', ld.full_name || 'Utilisateur');
          sessionStorage.setItem('lynkstor_staff_id', ld.staff_id || ld.staffId || '');
          applySessionRole();
          hideLoginGate();
          await bootstrap();
        } else {
          showLoginGate(json.message || 'Identifiants incorrects');
        }
      } catch (err) {
        showLoginGate(
          getApiBase()
            ? 'Impossible de joindre l’API Supabase/Node. Vérifiez la connexion.'
            : 'Impossible de joindre l’API. Vérifiez que le serveur est démarré.'
        );
      }
    });
  }

  document.getElementById('btn-logout')?.addEventListener('click', () => {
    setToken('');
    sessionStorage.removeItem('lynkstor_user_role');
    sessionStorage.removeItem('lynkstor_user_name');
    sessionStorage.removeItem('lynkstor_staff_id');
    showLoginGate('Déconnecté.');
  });

  // 1. Navigation Onglets
  const navItems = document.querySelectorAll('.nav-item');
  const tabPages = document.querySelectorAll('.tab-page');
  const pageTitle = document.getElementById('page-title');
  const pageSubtitle = document.getElementById('page-subtitle');

  const tabTitles = {
    dashboard: {
      title: 'Tableau de bord',
      subtitle: 'Vue d’ensemble des commerces, abonnements et activité terrain.',
    },
    map: {
      title: 'Carte',
      subtitle: 'Commerces abonnés et positions des agents terrain.',
    },
    subscribers: {
      title: 'Abonnements',
      subtitle: 'Forfaits, statuts et dates d’expiration.',
    },
    staff: {
      title: 'Équipe terrain',
      subtitle: 'Commerciaux, superviseurs et collectes.',
    },
    codes: {
      title: 'Codes d’activation',
      subtitle: 'Codes à donner aux clients pour créer un commerce cloud.',
    },
    users: {
      title: 'Utilisateurs clients',
      subtitle: 'Comptes rattachés aux commerces.',
    },
    sync: {
      title: 'Synchronisation',
      subtitle: 'Événements reçus depuis les applications mobiles.',
    },
    trial: {
      title: 'Période test',
      subtitle: 'Usage agrégé des boutiques du panel, sans données personnelles.',
    },
    settings: {
      title: 'Paramètres',
      subtitle: 'Endpoints mobile et clé API locale.',
    },
  };

  // 1b. Navigation mobile : sidebar hors-canvas (≤900 px).
  const mobileMenuBtn = document.getElementById('btn-mobile-menu');
  const sidebarScrim = document.getElementById('sidebar-scrim');
  function setSidebarOpen(open) {
    document.body.classList.toggle('sidebar-open', open);
    if (mobileMenuBtn) {
      mobileMenuBtn.setAttribute('aria-expanded', String(open));
      mobileMenuBtn.setAttribute('aria-label', open ? 'Fermer le menu de navigation' : 'Ouvrir le menu de navigation');
    }
  }
  mobileMenuBtn?.addEventListener('click', () => {
    setSidebarOpen(!document.body.classList.contains('sidebar-open'));
  });
  sidebarScrim?.addEventListener('click', () => setSidebarOpen(false));
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && document.body.classList.contains('sidebar-open')) setSidebarOpen(false);
  });

  navItems.forEach((item) => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const tab = item.getAttribute('data-tab');
      setSidebarOpen(false); // sur mobile, choisir un onglet referme le tiroir

      navItems.forEach((n) => n.classList.remove('active'));
      tabPages.forEach((p) => p.classList.remove('active'));

      item.classList.add('active');
      const targetPage = document.getElementById(`tab-${tab}`);
      if (targetPage) targetPage.classList.add('active');

      if (tabTitles[tab]) {
        pageTitle.textContent = tabTitles[tab].title;
        pageSubtitle.textContent = tabTitles[tab].subtitle;
      }

      if (tab === 'map') setTimeout(initMap, 200);
      if (tab === 'staff') loadStaff();
      if (tab === 'sync') loadSyncLogs();
      if (tab === 'users') loadUsers();
      if (tab === 'codes') loadRegistrationCodes();
      if (tab === 'trial') loadTrialAnalytics();
      if (tab === 'settings') refreshSettingsPanel();
    });
  });

  // 2. Rôles UI. Le serveur applique aussi ces droits route par route.
  const roleSelector = document.getElementById('active-role-selector');
  const userDisplayName = document.getElementById('user-display-name');
  const userDisplayRole = document.getElementById('user-display-role');

  const roleProfiles = {
    super_admin: { name: 'Administrateur', roleText: 'admin@lynkstor.com', avatar: 'AD' },
    supervisor: { name: 'Superviseur', roleText: 'Vue régionale', avatar: 'SU' },
    commercial: { name: 'Commercial', roleText: 'Vue terrain', avatar: 'CO' },
  };

  function applyRoleProfile(role) {
    const prof = roleProfiles[role] || roleProfiles.super_admin;
    const sessionName = sessionStorage.getItem('lynkstor_user_name');
    if (userDisplayName) userDisplayName.textContent = sessionName || prof.name;
    if (userDisplayRole) userDisplayRole.textContent = prof.roleText;
    const av = document.getElementById('user-avatar');
    if (av) av.textContent = prof.avatar;

    document.querySelectorAll('.admin-only').forEach((el) => {
      el.style.display = ['admin', 'super_admin'].includes(role) ? '' : 'none';
    });
    if (role === 'supervisor') {
      document.querySelectorAll('.supervisor-only').forEach((el) => {
        el.style.display = '';
      });
    }
  }

  function applySessionRole() {
    const role = sessionStorage.getItem('lynkstor_user_role') || 'super_admin';
    if (roleSelector) {
      roleSelector.value = role === 'admin' ? 'super_admin' : role;
      roleSelector.disabled = !['admin', 'super_admin'].includes(role);
    }
    applyRoleProfile(role);
  }

  roleSelector?.addEventListener('change', (e) => {
    const sessionRole =
      sessionStorage.getItem('lynkstor_user_role') || 'super_admin';
    if (!['admin', 'super_admin'].includes(sessionRole)) {
      applySessionRole();
      return;
    }
    applyRoleProfile(e.target.value);
  });

  // 3. Stats
  async function loadStats() {
    try {
      const res = await api('/api/v1/admin/stats');
      const json = await res.json();
      if (isOk(json)) {
        const d = json.data;
        setText('kpi-sales', `${Number(d.totalSalesFcfa).toLocaleString()} FCFA`);
        setText('kpi-subs', `${d.activeSubscriptions} / ${d.totalBusinesses}`);
        setText(
          'kpi-field-collections',
          `${Number(d.totalFieldCollectionsFcfa).toLocaleString()} FCFA`
        );
        setText('kpi-codes', `${d.availableCodes} / ${d.totalCodes}`);
        setText('kpi-codes-meta', `${d.availableCodes} libres · ${d.usedCodes} utilisées`);
        setText('kpi-sync', `${d.totalSyncEvents} Evts`);
        setText('active-subs-badge', String(d.activeSubscriptions));
        initChart(d.totalSalesFcfa);
      }
    } catch (e) {
      if (e.message !== 'UNAUTHORIZED') console.error('Error loading stats:', e);
    }
  }

  function setText(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  }

  function initChart(totalSales) {
    const ctx = document.getElementById('salesChart');
    if (!ctx) return;
    if (salesChart) salesChart.destroy();

    // Courbe indicative plafonnée au total réel (pas de fausse série marketing)
    const total = Number(totalSales) || 0;
    const series =
      total > 0
        ? [0.2, 0.28, 0.37, 0.45, 0.6, 0.82, 1].map((r) => Math.round(total * r))
        : [0, 0, 0, 0, 0, 0, 0];

    salesChart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: ['J-6', 'J-5', 'J-4', 'J-3', 'J-2', 'J-1', 'Aujourd’hui'],
        datasets: [
          {
            label: 'Volume (FCFA)',
            data: series,
            borderColor: '#1e3a5f',
            backgroundColor: 'rgba(30, 58, 95, 0.08)',
            fill: true,
            tension: 0.3,
            pointRadius: 3,
            pointBackgroundColor: '#1e3a5f',
            borderWidth: 2,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: true,
        plugins: {
          legend: { display: false },
          tooltip: {
            backgroundColor: '#111827',
            titleFont: { size: 12 },
            bodyFont: { size: 12 },
            padding: 10,
          },
        },
        scales: {
          x: {
            grid: { color: '#f3f4f6', drawBorder: false },
            ticks: { color: '#6b7280', font: { size: 11 } },
          },
          y: {
            grid: { color: '#f3f4f6', drawBorder: false },
            ticks: { color: '#6b7280', font: { size: 11 } },
          },
        },
      },
    });
  }

  // 4. Carte
  function initMap() {
    const container = document.getElementById('map-container');
    if (!container) return;

    if (!map) {
      map = L.map('map-container').setView([5.3484, -4.0305], 13);
      L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
        attribution: '&copy; OpenStreetMap, &copy; CARTO',
        maxZoom: 19,
      }).addTo(map);
    }
    loadMapData();
  }

  async function loadMapData() {
    if (!map) return;
    try {
      const res = await api('/api/v1/admin/map-data');
      const json = await res.json();

      if (isOk(json)) {
        mapMarkers.forEach((m) => map.removeLayer(m));
        mapMarkers = [];

        const { businesses, commercials } = json.data;

        const CITY_COORDS = {
          'douala': { lat: 4.0511, lng: 9.7679 },
          'yaoundé': { lat: 3.8480, lng: 11.5021 },
          'yaounde': { lat: 3.8480, lng: 11.5021 },
          'bamenda': { lat: 5.9631, lng: 10.1591 },
          'bafoussam': { lat: 5.4778, lng: 10.4176 },
          'garoua': { lat: 9.3014, lng: 13.3977 },
          'maroua': { lat: 10.5910, lng: 14.3159 },
          'kumba': { lat: 4.6364, lng: 9.4469 },
          'ngaoundéré': { lat: 7.3167, lng: 13.5833 },
          'ngaoundere': { lat: 7.3167, lng: 13.5833 },
          'kribi': { lat: 2.9372, lng: 9.9077 },
          'limbe': { lat: 4.0244, lng: 9.2049 },
          'bertoua': { lat: 4.5772, lng: 13.6847 },
          'ebolowa': { lat: 2.9000, lng: 11.1500 },
          'abidjan': { lat: 5.3484, lng: -4.0305 },
          'yamoussoukro': { lat: 6.8276, lng: -5.2893 },
          'bouaké': { lat: 7.6900, lng: -5.0300 },
          'bouake': { lat: 7.6900, lng: -5.0300 },
          'san-pédro': { lat: 4.7485, lng: -6.6363 },
          'san pedro': { lat: 4.7485, lng: -6.6363 },
          'libreville': { lat: 0.4162, lng: 9.4673 },
          'kinshasa': { lat: -4.4419, lng: 15.2663 },
          'dakar': { lat: 14.7167, lng: -17.4677 },
        };

        businesses.forEach((b) => {
          let lat = b.latitude ? Number(b.latitude) : null;
          let lng = b.longitude ? Number(b.longitude) : null;
          const cityKey = (b.city || '').trim().toLowerCase();

          if (!lat || !lng || (lat === 5.3484 && lng === -4.0305)) {
            if (cityKey && CITY_COORDS[cityKey]) {
              lat = CITY_COORDS[cityKey].lat;
              lng = CITY_COORDS[cityKey].lng;
            } else if (cityKey.includes('yaound')) {
              lat = 3.8480; lng = 11.5021;
            } else if (cityKey.includes('douala')) {
              lat = 4.0511; lng = 9.7679;
            } else {
              lat = 4.0511; lng = 9.7679; // Default Douala fallback
            }
          }

          const isActive = b.sub_status === 'active';
          const iconHtml = `<div class="custom-shop-pin ${isActive ? 'pin-active' : 'pin-expired'}"><i class="fa-solid fa-store"></i></div>`;
          const customIcon = L.divIcon({
            html: iconHtml,
            className: 'shop-div-icon',
            iconSize: [32, 32],
          });

          const popupContent = `
            <div style="color:#111827; min-width:160px;">
              <div style="font-weight:600; font-size:13px; margin-bottom:4px;">${escapeHtml(b.name)}</div>
              <div style="font-size:12px; color:#6b7280;">${escapeHtml(b.owner_name || '')} · ${escapeHtml(b.phone || '')}</div>
              <div style="font-size:12px; margin-top:6px;">${escapeHtml(b.plan_name || 'Sans forfait')} — <span style="color:${isActive ? '#047857' : '#b91c1c'}; font-weight:600;">${isActive ? 'Actif' : 'Expiré'}</span></div>
            </div>
          `;

          const marker = L.marker([lat, lng], { icon: customIcon })
            .addTo(map)
            .bindPopup(popupContent);
          mapMarkers.push(marker);
        });

        commercials.forEach((c) => {
          if (!c.current_lat || !c.current_lng) return;

          const iconHtml = `<div class="custom-agent-pin"><i class="fa-solid fa-person-walking"></i></div>`;
          const customIcon = L.divIcon({
            html: iconHtml,
            className: 'agent-div-icon',
            iconSize: [36, 36],
          });

          const popupContent = `
            <div style="color:#111827; min-width:140px;">
              <div style="font-weight:600; font-size:13px;">${escapeHtml(c.full_name)}</div>
              <div style="font-size:12px; color:#6b7280; margin-top:2px;">Agent commercial</div>
              <div style="font-size:12px; margin-top:4px;">${escapeHtml(c.phone || '')}</div>
            </div>
          `;

          const marker = L.marker([c.current_lat, c.current_lng], { icon: customIcon })
            .addTo(map)
            .bindPopup(popupContent);
          mapMarkers.push(marker);
        });

        setText('gps-active-badge', `${mapMarkers.length} Pins`);
      }
    } catch (e) {
      if (e.message !== 'UNAUTHORIZED') console.error('Error loading map data:', e);
    }
  }

  document.getElementById('btn-recenter-map')?.addEventListener('click', () => {
    if (map) map.setView([5.3484, -4.0305], 13);
  });

  // 5. Activités terrain
  async function loadFieldActivities() {
    try {
      const res = await api('/api/v1/admin/field-activities');
      const json = await res.json();
      if (isOk(json)) {
        const list = document.getElementById('field-activity-list');
        if (!list) return;
        const items = json.data || [];
        if (!items.length) {
          list.innerHTML =
            '<p class="help-text" style="margin:0;">Aucune activité terrain pour le moment.</p>';
          return;
        }
        list.innerHTML = items
          .map(
            (a) => `
          <div class="recent-item">
            <div class="recent-info">
              <h5>${escapeHtml(a.business_name)}</h5>
              <p>${escapeHtml(a.staff_name)} · ${new Date(a.created_at).toLocaleString()}</p>
            </div>
            <div class="recent-amount">${Number(a.amount_collected_fcfa).toLocaleString()} FCFA</div>
          </div>
        `
          )
          .join('');
      }
    } catch (e) {
      if (e.message !== 'UNAUTHORIZED') console.error('Error loading field activities:', e);
    }
  }

  // 6. Abonnés
  let allSubscribers = [];

  async function loadSubscribers() {
    try {
      const res = await api('/api/v1/admin/subscriptions');
      const json = await res.json();
      if (isOk(json)) {
        allSubscribers = json.data || [];
        renderSubscribers(allSubscribers);
        populateBusinessSelect(allSubscribers);
      }
    } catch (e) {
      if (e.message !== 'UNAUTHORIZED') console.error('Error loading subscribers:', e);
    }
  }

  function populateBusinessSelect(list) {
    const select = document.getElementById('express-business-select');
    if (!select) return;
    select.innerHTML = list
      .map(
        (s) =>
          `<option value="${escapeAttr(s.business_id)}">${escapeHtml(s.business_name)} (${escapeHtml(s.owner_name || '')})</option>`
      )
      .join('');
  }

  function renderSubscribers(list) {
    const tbody = document.getElementById('subscribers-table-body');
    if (!tbody) return;

    tbody.innerHTML = list
      .map((sub) => {
        let planClass = 'plan-pro';
        const plan = sub.plan_name || '';
        if (plan.includes('ENTERPRISE')) planClass = 'plan-enterprise';
        if (plan.includes('STARTER')) planClass = 'plan-starter';
        if (plan.includes('GRATUIT')) planClass = 'plan-gratuit';

        let statusBadge = '<span class="status-badge status-active">Actif</span>';
        if (sub.status === 'expired') {
          statusBadge = '<span class="status-badge status-expired">Expiré</span>';
        }
        if (sub.status === 'suspended') {
          statusBadge = '<span class="status-badge status-suspended">Suspendu</span>';
        }

        return `
        <tr>
          <td><code>${escapeHtml(sub.id)}</code></td>
          <td><strong>${escapeHtml(sub.business_name)}</strong></td>
          <td>${escapeHtml(sub.owner_name || '')}<br><span style="color:var(--text-muted);font-size:12px;">${escapeHtml(sub.phone || '')}</span></td>
          <td><span class="plan-badge ${planClass}">${escapeHtml(plan)}</span></td>
          <td>${statusBadge}</td>
          <td>${Number(sub.price_fcfa || 0).toLocaleString()} FCFA</td>
          <td>${sub.expires_at ? new Date(sub.expires_at).toLocaleDateString() : '—'}</td>
          <td>
            <button type="button" class="btn btn-outline btn-sm btn-edit-sub" data-id="${escapeAttr(sub.id)}">
              Modifier
            </button>
          </td>
        </tr>
      `;
      })
      .join('');

    document.querySelectorAll('.btn-edit-sub').forEach((btn) => {
      btn.addEventListener('click', () => {
        const id = btn.getAttribute('data-id');
        const sub = allSubscribers.find((s) => s.id === id);
        if (sub) openEditSubModal(sub);
      });
    });
  }

  // 7. Staff
  let allStaff = [];

  async function loadStaff() {
    try {
      const res = await api('/api/v1/admin/staff');
      const json = await res.json();
      if (isOk(json)) {
        allStaff = json.data || [];
        renderStaff(allStaff);
        populateStaffSelect(allStaff);
      }
    } catch (e) {
      if (e.message !== 'UNAUTHORIZED') console.error('Error loading staff:', e);
    }
  }

  function populateStaffSelect(list) {
    const select = document.getElementById('express-staff-select');
    if (!select) return;
    select.innerHTML = list
      .filter((s) => s.role === 'commercial')
      .map(
        (s) =>
          `<option value="${escapeAttr(s.id)}">${escapeHtml(s.full_name)} (${escapeHtml(s.phone || '')})</option>`
      )
      .join('');
  }

  function renderStaff(list) {
    const tbody = document.getElementById('staff-table-body');
    if (!tbody) return;

    const roleLabel = {
      commercial: 'Commercial',
      supervisor: 'Superviseur',
      super_admin: 'Administrateur',
    };
    const isSuperAdmin =
      (sessionStorage.getItem('lynkstor_user_role') || 'super_admin') === 'super_admin';

    tbody.innerHTML = list
      .map(
        (st) => `
      <tr>
        <td><code>${escapeHtml(st.id)}</code></td>
        <td><strong>${escapeHtml(st.full_name)}</strong></td>
        <td>${escapeHtml(st.phone || '—')}</td>
        <td>${escapeHtml(roleLabel[st.role] || st.role || '—')}</td>
        <td><span class="status-badge ${st.status === 'active' ? 'status-active' : 'status-suspended'}">${escapeHtml(st.status === 'active' ? 'Actif' : st.status === 'disabled' ? 'Désactivé' : st.status || '—')}</span></td>
        <td>${Number(st.total_activations || 0)}</td>
        <td>${Number(st.total_collected_fcfa || 0).toLocaleString()} FCFA</td>
        <td>${st.last_ping_at ? new Date(st.last_ping_at).toLocaleString() : '—'}</td>
        <td class="table-actions">${
          isSuperAdmin && st.id !== sessionStorage.getItem('lynkstor_staff_id')
            ? st.status === 'active'
              ? `<button type="button" class="btn btn-sm btn-outline" data-staff-action="disable" data-id="${escapeAttr(st.id)}">Révoquer / désactiver</button>`
              : `<button type="button" class="btn btn-sm btn-outline" data-staff-action="enable" data-id="${escapeAttr(st.id)}">Réactiver</button>`
            : '—'
        }</td>
      </tr>
    `
      )
      .join('');
  }

  // Révocation de session : désactiver/réactiver bump token_version côté
  // gateway, donc TOUTES les sessions déjà émises pour ce compte tombent à la
  // requête suivante (401 -> portail de login automatiquement).
  document.getElementById('staff-table-body')?.addEventListener('click', async (e) => {
    const btn = e.target.closest('[data-staff-action]');
    if (!btn) return;
    const action = btn.getAttribute('data-staff-action');
    const id = btn.getAttribute('data-id');
    const nextStatus = action === 'disable' ? 'disabled' : 'active';
    if (action === 'disable' && !confirm('Désactiver ce compte et révoquer immédiatement toutes ses sessions ?')) return;
    btn.disabled = true;
    try {
      const res = await api('/api/v1/admin/staff/update', {
        method: 'POST',
        body: JSON.stringify({ id, status: nextStatus }),
      });
      const json = await res.json();
      if (isOk(json)) {
        await loadStaff();
      } else {
        alert(json.message || 'Échec de la mise à jour.');
        btn.disabled = false;
      }
    } catch (err) {
      if (err.message !== 'UNAUTHORIZED') alert(err.message);
      btn.disabled = false;
    }
  });

  // Users
  async function loadUsers() {
    const tbody = document.getElementById('users-table-body');
    if (!tbody) return;
    try {
      const res = await api('/api/v1/admin/users');
      const json = await res.json();
      if (isOk(json)) {
        tbody.innerHTML = (json.data || [])
          .map(
            (u) => `
          <tr>
            <td><strong>${escapeHtml(u.full_name)}</strong><br><code>${escapeHtml(u.id)}</code></td>
            <td>${escapeHtml(u.business_name || '—')}</td>
            <td>${escapeHtml(u.phone || '—')}</td>
            <td>${escapeHtml(u.role || '—')}</td>
            <td>${escapeHtml(u.plan_name || u.sub_status || '—')}</td>
            <td>${escapeHtml(u.status === 'active' ? 'Actif' : u.status || '—')}</td>
          </tr>
        `
          )
          .join('');
      }
    } catch (e) {
      if (e.message !== 'UNAUTHORIZED') console.error(e);
    }
  }

  // Sync logs
  async function loadSyncLogs() {
    const tbody = document.getElementById('sync-table-body');
    if (!tbody) return;
    try {
      const res = await api('/api/v1/admin/sync-logs');
      const json = await res.json();
      if (isOk(json)) {
        tbody.innerHTML = (json.data || [])
          .map(
            (s) => `
          <tr>
            <td><code>${escapeHtml(s.id)}</code></td>
            <td>${escapeHtml(s.business_name || s.business_id)}</td>
            <td>${escapeHtml(s.entity_type || '')}</td>
            <td>${escapeHtml(s.entity_id || '')}</td>
            <td>${escapeHtml(s.operation || '')}</td>
            <td>${s.created_at ? new Date(s.created_at).toLocaleString() : ''}</td>
          </tr>
        `
          )
          .join('');
      }
    } catch (e) {
      if (e.message !== 'UNAUTHORIZED') console.error(e);
    }
  }

  async function loadTrialAnalytics() {
    const tbody = document.getElementById('trial-table-body');
    try {
      const res = await api('/api/v1/admin/analytics/summary');
      const json = await res.json();
      if (!isOk(json)) return;
      const d = json.data || {};
      const setText = (id, value) => {
        const el = document.getElementById(id);
        if (el) el.textContent = value;
      };
      setText('trial-installs', d.installs ?? 0);
      setText('trial-events', d.events ?? 0);
      setText('trial-sales', d.totalSales ?? 0);
      setText('trial-sold', Number(d.totalSoldFcfa || 0).toLocaleString('fr-FR'));
      if (tbody) {
        const shops = d.shops || [];
        tbody.innerHTML = shops.length
          ? shops
              .map((s) => {
                const id = String(s.install_id || '').slice(0, 8);
                return `<tr>
                  <td><code>${escapeHtml(id)}</code></td>
                  <td>${escapeHtml(s.sector || '—')}</td>
                  <td>${s.sales_count ?? 0}</td>
                  <td>${Number(s.sold_fcfa || 0).toLocaleString('fr-FR')}</td>
                  <td>${s.catalog_activated_count ?? 0}</td>
                  <td>${s.open_days ?? 0}</td>
                  <td>${s.captured_at ? new Date(s.captured_at).toLocaleString() : ''}</td>
                </tr>`;
              })
              .join('')
          : '<tr><td colspan="7" style="text-align:center;color:var(--text-muted);padding:20px;">Aucune donnée reçue pour le moment.</td></tr>';
      }
    } catch (e) {
      if (e.message !== 'UNAUTHORIZED') console.error(e);
    }
  }

  document.getElementById('btn-export-trial')?.addEventListener('click', async () => {
    try {
      const res = await api('/api/v1/admin/analytics/export');
      const json = await res.json();
      const blob = new Blob([JSON.stringify(json.data || [], null, 2)], {
        type: 'application/json',
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `lynkstor-periode-test-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      if (e.message !== 'UNAUTHORIZED') alert('Export impossible.');
    }
  });

  // Settings
  function refreshSettingsPanel() {
    const base = getApiBase() || window.location.origin;
    const urlInput = document.getElementById('server-url-display');
    if (urlInput) {
      urlInput.value = `${base}/api/v1/sync/push`;
    }
    const pullInput = document.getElementById('server-pull-url-display');
    if (pullInput) {
      pullInput.value = `${base}/api/v1/sync/pull?businessId=VOTRE_BUSINESS_ID`;
    }
    const tokenDisplay = document.getElementById('api-token-display');
    if (tokenDisplay) {
      const t = getToken();
      tokenDisplay.value = t ? `${t.slice(0, 6)}…${t.slice(-4)}` : '(non connecté)';
    }
    const apiBaseDisplay = document.getElementById('api-base-display');
    if (apiBaseDisplay) {
      apiBaseDisplay.value = getApiBase() || '(même origine — monolithe)';
    }
    const apiBaseInput = document.getElementById('api-base-input');
    if (apiBaseInput && !apiBaseInput.value) {
      apiBaseInput.placeholder = getApiBase() || 'https://votre-api.onrender.com';
    }
  }

  document.getElementById('btn-save-api-base')?.addEventListener('click', () => {
    const input = document.getElementById('api-base-input');
    if (!input) return;
    const v = input.value.trim().replace(/\/$/, '');
    if (v) localStorage.setItem(API_BASE_KEY, v);
    else localStorage.removeItem(API_BASE_KEY);
    refreshSettingsPanel();
    alert(v ? 'URL API enregistrée.' : 'URL API effacée (même origine).');
  });

  document.getElementById('btn-copy-url')?.addEventListener('click', () => {
    const el = document.getElementById('server-url-display');
    if (el) navigator.clipboard?.writeText(el.value);
  });

  document.getElementById('btn-save-token')?.addEventListener('click', () => {
    const input = document.getElementById('api-token-input');
    if (input && input.value.trim()) {
      setToken(input.value.trim());
      input.value = '';
      refreshSettingsPanel();
      alert('Clé API enregistrée localement.');
      bootstrap();
    }
  });

  // Activation express — URL corrigée sous /admin
  const modalExpress = document.getElementById('modal-express-activate');
  const formExpress = document.getElementById('form-express-activate');

  document.getElementById('btn-express-activate')?.addEventListener('click', () => {
    modalExpress?.classList.add('active');
  });

  formExpress?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const body = {
      business_id: document.getElementById('express-business-select').value,
      staff_id: document.getElementById('express-staff-select').value,
      plan_name: document.getElementById('express-plan-select').value,
      price_fcfa: parseFloat(document.getElementById('express-price-input').value),
      duration_months: parseInt(document.getElementById('express-duration-select').value, 10),
      notes: document.getElementById('express-notes-input').value,
    };

    try {
      const res = await api('/api/v1/admin/commercial/activate', {
        method: 'POST',
        body: JSON.stringify(body),
      });
      const json = await res.json();
      if (isOk(json)) {
        alert(json.message);
        modalExpress.classList.remove('active');
        await loadSubscribers();
        await loadStats();
        await loadFieldActivities();
        if (map) loadMapData();
      } else {
        alert(json.message || 'Échec activation');
      }
    } catch (err) {
      if (err.message !== 'UNAUTHORIZED') console.error('Failed to express activate:', err);
    }
  });

  // Modal édition sub
  const modalEditSub = document.getElementById('modal-edit-sub');
  const formEditSub = document.getElementById('form-edit-sub');

  function openEditSubModal(sub) {
    document.getElementById('edit-sub-id').value = sub.id;
    document.getElementById('edit-sub-business').value = sub.business_name;
    document.getElementById('edit-sub-plan').value = sub.plan_name;
    document.getElementById('edit-sub-price').value = sub.price_fcfa;
    document.getElementById('edit-sub-status').value = sub.status;
    document.getElementById('edit-sub-expires').value = sub.expires_at
      ? String(sub.expires_at).split('T')[0]
      : '';
    modalEditSub?.classList.add('active');
  }

  formEditSub?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const id = document.getElementById('edit-sub-id').value;
    const body = {
      plan_name: document.getElementById('edit-sub-plan').value,
      price_fcfa: parseFloat(document.getElementById('edit-sub-price').value),
      status: document.getElementById('edit-sub-status').value,
      expires_at: document.getElementById('edit-sub-expires').value,
    };

    try {
      const res = await api(`/api/v1/admin/subscriptions/${id}`, {
        method: 'PUT',
        body: JSON.stringify(body),
      });
      const json = await res.json();
      if (isOk(json)) {
        modalEditSub.classList.remove('active');
        await loadSubscribers();
        await loadStats();
      }
    } catch (err) {
      if (err.message !== 'UNAUTHORIZED') console.error('Failed to update subscription:', err);
    }
  });

  // Codes d'activation
  async function loadRegistrationCodes() {
    const tbody = document.getElementById('codes-table-body');
    if (!tbody) return;
    try {
      const res = await api('/api/v1/admin/codes');
      const json = await res.json();
      if (!isOk(json)) return;
      const rows = json.data || [];
      if (!rows.length) {
        tbody.innerHTML =
          '<tr><td colspan="8" style="color:var(--text-muted);text-align:center;padding:20px;">Aucune clé d’activation disponible. Générez-en pour vos commerciaux.</td></tr>';
        return;
      }
      tbody.innerHTML = rows
        .map((c) => {
          // Statuts Neon : available | reserved | used | void
          let st = '<span class="status-badge status-active">Disponible</span>';
          if (c.status === 'used') st = '<span class="status-badge status-expired">Utilisé</span>';
          if (c.status === 'void') st = '<span class="status-badge status-suspended">Révoqué</span>';
          if (c.status === 'reserved') st = '<span class="status-badge status-suspended">Réservé</span>';

          const actDate = c.used_at ? new Date(c.used_at).toLocaleString() : '—';
          const bizText = c.used_by_business_name
            ? `<strong>${escapeHtml(c.used_by_business_name)}</strong>`
            : escapeHtml(c.used_by_business || c.business_name || '—');

          const revokeBtn = c.status === 'available'
            ? `<button type="button" class="btn btn-outline btn-sm btn-revoke-code" data-code="${escapeAttr(c.code)}" style="color:var(--danger,#ef4444);margin-left:4px;">Révoquer</button>`
            : '';

          return `<tr>
            <td>
              <code style="font-size:14px;font-weight:700;letter-spacing:1px;color:var(--primary);">${escapeHtml(c.code)}</code>
              <button type="button" class="btn btn-outline btn-sm btn-copy-code" data-code="${escapeAttr(c.code)}" style="padding:2px 6px;margin-left:6px;font-size:11px;" title="Copier la clé">
                <i class="fa-solid fa-copy"></i>
              </button>
            </td>
            <td><strong>${escapeHtml(c.assigned_staff_name || c.assigned_staff || '—')}</strong></td>
            <td><span class="plan-badge plan-pro">${escapeHtml(c.plan_name || 'STARTER')}</span></td>
            <td>${escapeHtml(c.owner_phone || c.business_name || '—')}</td>
            <td>${st}</td>
            <td>${bizText}</td>
            <td>${escapeHtml(actDate)}</td>
            <td>${revokeBtn}</td>
          </tr>`;
        })
        .join('');

      // Actions sur le tableau des codes
      document.querySelectorAll('.btn-copy-code').forEach((btn) => {
        btn.addEventListener('click', () => {
          const code = btn.getAttribute('data-code');
          if (code) {
            navigator.clipboard?.writeText(code);
            alert(`Clé d'activation ${code} copiée dans le presse-papier.`);
          }
        });
      });

      document.querySelectorAll('.btn-revoke-code').forEach((btn) => {
        btn.addEventListener('click', async () => {
          const code = btn.getAttribute('data-code');
          if (!code || !confirm(`Êtes-vous sûr de vouloir révoquer la clé ${code} ?`)) return;
          try {
            const res = await api('/api/v1/admin/codes/revoke', {
              method: 'POST',
              body: JSON.stringify({ code }),
            });
            const json = await res.json();
            if (isOk(json)) {
              alert(json.message);
              await loadRegistrationCodes();
              await loadStats();
            } else {
              alert(json.message || 'Échec de la révocation');
            }
          } catch (err) {
            if (err.message !== 'UNAUTHORIZED') console.error('Revoke code error:', err);
          }
        });
      });
    } catch (e) {
      if (e.message !== 'UNAUTHORIZED') console.error(e);
    }
  }

  const modalCodes = document.getElementById('modal-generate-codes');
  document.getElementById('btn-generate-codes')?.addEventListener('click', async () => {
    await loadStaff();
    const sel = document.getElementById('code-staff-select');
    if (sel) {
      const eligibleStaff = (allStaff || []).filter(
        (s) => s.role === 'commercial' || s.role === 'supervisor' || s.role === 'super_admin'
      );
      if (eligibleStaff.length > 0) {
        sel.innerHTML = eligibleStaff
          .map((s) => `<option value="${escapeAttr(s.id)}">${escapeHtml(s.full_name)} (${escapeHtml(s.phone || s.role || 'Commercial')})</option>`)
          .join('');
      } else {
        sel.innerHTML = `
          <option value="st-01">Amadou Koné (Commercial)</option>
          <option value="st-02">Bamba Sidiki (Commercial)</option>
          <option value="st-03">Kouassi Jean (Superviseur)</option>
          <option value="st-04">Super Admin Lynkstor</option>
        `;
      }
    }
    modalCodes?.classList.add('active');
  });

  document.getElementById('form-generate-codes')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const body = {
      assignedStaff: document.getElementById('code-staff-select').value || '',
      count: parseInt(document.getElementById('code-count-input').value, 10) || 1,
    };
    try {
      const res = await api('/api/v1/admin/codes/generate', {
        method: 'POST',
        body: JSON.stringify(body),
      });
      const json = await res.json();
      if (isOk(json)) {
        const gd = json.data || {};
        const codesStr = (gd.codes || []).join('\n');
        alert(`✅ ${json.message || (gd.count + ' code(s) généré(s)')} :\n\n${codesStr}\n\nTransmettez ces clés au commercial.`);
        modalCodes?.classList.remove('active');
        await loadRegistrationCodes();
        await loadStats();
      } else {
        alert(json.message || 'Échec génération');
      }
    } catch (err) {
      if (err.message !== 'UNAUTHORIZED') console.error(err);
    }
  });

  // Modal staff
  const modalAddStaff = document.getElementById('modal-add-staff');
  const formAddStaff = document.getElementById('form-add-staff');

  document.getElementById('btn-add-staff')?.addEventListener('click', () => {
    modalAddStaff?.classList.add('active');
  });

  formAddStaff?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const body = {
      full_name: document.getElementById('staff-name-input').value,
      username: document.getElementById('staff-username-input')?.value || '',
      password: document.getElementById('staff-password-input')?.value || '',
      email: document.getElementById('staff-email-input').value,
      phone: document.getElementById('staff-phone-input').value,
      role: document.getElementById('staff-role-select').value,
    };

    try {
      const res = await api('/api/v1/admin/staff', {
        method: 'POST',
        body: JSON.stringify(body),
      });
      const json = await res.json();
      if (isOk(json)) {
        const sd = json.data || {};
        alert(`✅ ${json.message || 'Compte créé.'}\nIdentifiant: ${sd.username || body.username}`);
        modalAddStaff.classList.remove('active');
        formAddStaff.reset();
        await loadStaff();
      } else {
        alert(json.message || 'Échec création');
      }
    } catch (err) {
      if (err.message !== 'UNAUTHORIZED') console.error('Failed to create staff:', err);
    }
  });

  document.querySelectorAll('.close-modal').forEach((b) => {
    b.addEventListener('click', () => {
      modalExpress?.classList.remove('active');
      modalEditSub?.classList.remove('active');
      modalAddStaff?.classList.remove('active');
      modalCodes?.classList.remove('active');
    });
  });

  document.getElementById('btn-refresh')?.addEventListener('click', () => {
    bootstrap();
  });

  function escapeHtml(str) {
    return String(str ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function escapeAttr(str) {
    return escapeHtml(str).replace(/'/g, '&#39;');
  }

  async function bootstrap() {
    if (!getToken()) {
      showLoginGate('Connectez-vous pour accéder au tableau de bord.');
      return;
    }
    applySessionRole();
    hideLoginGate();
    const role = sessionStorage.getItem('lynkstor_user_role') || 'super_admin';
    const loaders = [
      loadStats(),
      loadSubscribers(),
      loadFieldActivities(),
    ];
    if (['admin', 'super_admin', 'supervisor'].includes(role)) {
      loaders.push(loadStaff(), loadRegistrationCodes());
    }
    await Promise.all(loaders);
    refreshSettingsPanel();
  }

  bootstrap();
});
