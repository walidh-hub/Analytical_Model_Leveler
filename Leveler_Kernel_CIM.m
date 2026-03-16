function [Metrics, Data] = Leveler_Kernel_CIM(p)
% LEVELER_KERNEL_CIM v2.0 (Extended Domain with Entry/Exit Tables)
% Analytical solver based on curvature integration.
% Includes boundary conditions for entry/exit tables (Clamped ends).

    %% 1. GEOMETRIC SETUP & EXTENDED DOMAIN
    
    % A. Control the presence of fileds
    fields = {'I_in', 'I_out', 'K0', 'N', 't'};
    for f = fields
        if ~isfield(p, f{1})
            error('Campo mancante nella struttura p: %s', f{1});
        end

        if isempty(p.(f{1}))
            error('Campo vuoto nella struttura p: %s', f{1})
        end
    end

    % B. Machine Physical Rollers
    Xc_mach = ((0:p.N-1) * p.P)';
    R_eff = p.R + p.t/2;
    
    I_base_long = linspace(p.I_in, p.I_out, p.N)';
    %y_norm = (2 * p.y_coord / p.W)^2;
    %Delta_I_y = p.Fc * (1 - y_norm) + p.Fl * y_norm;
    
    Yc_mach = zeros(p.N, 1);
    Target_Surface_Mach = zeros(p.N, 1); % Where the sheet should touch
    Is_Active_Mach = true(p.N, 1);

    Gap_Threshold = -0.1;

    for i = 1:p.N
        % 1. Intermesh Base (Tilt)
        intermesh_base = I_base_long(i);
        
        % 2. Applica Correzione Flex (Fc/Fl) all'Intermesh Efficace
        % Questo assicura che la modifica di Fc/Fl muova effettivamente i rulli
        effective_intermesh = intermesh_base; % + Delta_I_y;

        if mod(i,2) ~= 0 
            % --- Lower Roller (Fixed Bank) ---
            % I rulli inferiori sono il riferimento (Passline fissa a 0 sulla sommità)
            Yc_mach(i) = -R_eff; 
            Target_Surface_Mach(i) = 0; 
        else
            % --- Upper Roller (Adjustable Bank) ---
            % I rulli superiori scendono per creare l'intermesh richiesto (incluso Fc/Fl)
            Yc_mach(i) = R_eff - effective_intermesh; 
            Target_Surface_Mach(i) = Yc_mach(i) - R_eff; % La lamiera passa SOTTO
        end

        % Check attivazione rullo basato sull'intermesh reale
        if effective_intermesh < Gap_Threshold
            Is_Active_Mach(i) = false;
        end
    end
    
    % Entry (1) = Attivo, Machine (2..N+1) = Calcolato, Exit (End) = Attivo
    Is_Roller_Active = [true; Is_Active_Mach; true];

    % C. EXTEND DOMAIN (Entry/Exit Tables)
    % We add 2 virtual nodes: Index 1 (Entry), Index End (Exit)
    % The real machine rollers will be indices 2 to N+1
    
    L_ext = p.P; % Length of external tables (1 Pitch)
    
    % Global Coordinates
    Xc = [Xc_mach(1) - L_ext;  Xc_mach;  Xc_mach(end) + L_ext];
    
    % Target Surfaces (0 = Passline for tables)
    % Entry Table (0), Machine Targets, Exit Table (0)
    Y_targets = [0; Target_Surface_Mach; 0];
    
    % Machine Centers (For Plotting only, padded with NaNs or 0s)
    % Note: Virtual nodes don't have a "Roller Center", we just plot the constraint
    %Yc_plot = [NaN; Yc_mach; NaN]; 
    
    N_total = length(Xc);       % N + 2
    num_segments = N_total - 1; % N + 1

    %% 2. SEGMENT INITIALIZATION
    pts_per_span = 51;
    Segments(num_segments) = struct(); 
    
    for i = 1:num_segments
        Segments(i).L = Xc(i+1) - Xc(i); 
        Segments(i).s = linspace(0, Segments(i).L, pts_per_span)';
        Segments(i).x_global = Segments(i).s + Xc(i);
        
        Segments(i).Moment = zeros(pts_per_span, 1);
        Segments(i).Curvature = zeros(pts_per_span, 1);
        Segments(i).Slope = zeros(pts_per_span, 1);
        Segments(i).Deflection = zeros(pts_per_span, 1);
    end
    
    % Visualization Data
    Data.Machine.Xc = Xc_mach; % Plot only real rollers
    Data.Machine.Yc = Yc_mach;
    Data.Machine.R = p.R;
    Data.Machine.Y_targets = Y_targets; % Useful for debug

    %% 3. MATERIAL SETUP
    N_layers = 51;
    z_layers = linspace(-p.t/2, p.t/2, N_layers)';
    dz = z_layers(2) - z_layers(1);
    
    % History Variables
    if isfield(p, 'Initial_Sigma') && length(p.Initial_Sigma) == N_layers
    sigma_current = p.Initial_Sigma;
    else
        sigma_current = zeros(N_layers, 1);
    end
    
    if isfield(p, 'Initial_Eps_Pl') && length(p.Initial_Eps_Pl) == N_layers
        eps_pl_cum = p.Initial_Eps_Pl;
    else
        eps_pl_cum = zeros(N_layers, 1);
    end

    % Caricamento Memoria Plastica (Backstress) ---
    if isfield(p, 'Initial_Alpha') && length(p.Initial_Alpha) == N_layers
        alpha_current = p.Initial_Alpha; % Riprende dallo stato precedente
    else
        alpha_current = zeros(N_layers, 1); % Materiale Vergine
    end

    %% 4. CORE SOLVER LOOP (Robust Newton-Raphson)
    
    % A. Initial Guess
    % Simple geometric curvature guess based on targets
    Kappa_Guess = zeros(N_total, 1);
    for i = 2:N_total-1
        % Approximate 2nd derivative finite difference
        Kappa_Guess(i) = (Y_targets(i-1) - 2*Y_targets(i) + Y_targets(i+1)) / (p.P^2);
    end
    Kappa_Guess = Kappa_Guess * 0.5; % Relaxation
    
    % B. Solver Parameters
    max_iter = 100;
    tol = 1e-5;
    perturbation = 1e-6;
    damping = 0.5;
    
    Kappa_Solved = Kappa_Guess;
    
    % C. Iteration
    for iter = 1:max_iter
        Mismatch = solve_geometry_mismatch(Kappa_Solved);
        
        if norm(Mismatch) < tol, break; end
        
        % Jacobian Construction
        N_vars = length(Kappa_Solved);
        J = zeros(N_vars, N_vars);
        
        for j = 1:N_vars
            K_pert = Kappa_Solved;
            K_pert(j) = K_pert(j) + perturbation;
            M_pert = solve_geometry_mismatch(K_pert);
            J(:, j) = (M_pert - Mismatch) / perturbation;
        end
        
        % Robust Update
        if rcond(J) < 1e-12
            delta = -pinv(J) * Mismatch;
        else
            delta = -J \ Mismatch;
        end
        Kappa_Solved = Kappa_Solved + delta * damping;
    end
    
    % Final Call to populate Segments
    solve_geometry_mismatch(Kappa_Solved);
    Metrics.Curvature_Distribution = Kappa_Solved;

    %% 5. NESTED SOLVER FUNCTION
    function Mismatch = solve_geometry_mismatch(Kappa_Trial)
        
        % --- CLAMPED ENTRY CONDITION ---
        % Node 1 is the Entry Table (Virtual).
        % We assume the sheet comes in flat at height 0 (Passline).
        current_slope = 0; 
        current_deflection = Y_targets(1); % initial deflection
        
        Mismatch = zeros(N_total, 1);
        
        for h = 1:num_segments
            
            % Interpolate Curvature
            k_start = Kappa_Trial(h);
            k_end   = Kappa_Trial(h+1);
            
            L_seg = Segments(h).L;
            s_vec = Segments(h).s;
            
            k_dist = k_start + (k_end - k_start) * (s_vec / L_seg);
            
            % Integration
            slope_prof = current_slope + cumtrapz(s_vec, k_dist);
            defl_prof  = current_deflection + cumtrapz(s_vec, slope_prof);
            
            % Update Start for next segment
            current_slope = slope_prof(end);
            current_deflection = defl_prof(end);
            
            % --- CALCULATE ERROR at End of Segment (Node k+1) ---
            % Node index in global arrays
            idx_node = h + 1;
            
            if Is_Roller_Active(idx_node)
                % 1. Identifichiamo l'indice del rullo nella macchina (2..N+1 -> 1..N)
                idx_mach = idx_node - 1;

                if idx_node == N_total
                    Y_target = Y_targets(idx_node);
                else
                    % 2. Calcoliamo l'angolo di inclinazione della lamiera in quel punto
                    % slope = tan(theta) -> theta = atan(slope)
                    theta = atan(slope_prof(end));
                
                    % 3. Calcolo del Target Verticale Dinamico
                    % Il punto di contatto trasla sulla circonferenza in base a theta
                    if mod(idx_mach, 2) ~= 0 
                        % Rulli Inferiori: contatto sulla parte superiore (Yc + R*cos)
                        % La lamiera "poggia" sul rullo
                        Y_target = Yc_mach(idx_mach) + R_eff * cos(theta); 
                    else
                        % Rulli Superiori: contatto sulla parte inferiore (Yc - R*cos)
                        % La lamiera "preme" sotto il rullo
                        Y_target = Yc_mach(idx_mach) - R_eff * cos(theta);
                    end
                end

                % CASO STANDARD: Il rullo tocca -> Imponiamo il passaggio per la superficie
                Mismatch(idx_node) = current_deflection - Y_target;
            else
                % CASO GAP APERTO: Il rullo non tocca -> Imponiamo Curvatura Nulla (Relax)
                % Invece di forzare la posizione Y (che causerebbe onde),
                % forziamo il solutore a scegliere una curvatura zero in questo punto.
                % Moltiplichiamo per un fattore di scala per bilanciare l'ordine di grandezza nell'errore
                scale_factor = 1000; 
                Mismatch(idx_node) = Kappa_Trial(idx_node) * scale_factor;
            end
            
            % Store Data
            Segments(h).Curvature = k_dist;
            Segments(h).Slope = slope_prof;
            Segments(h).Deflection = defl_prof;
        end
        
        % Mismatch at Node 1 is implicitly 0 due to init conditions
        Mismatch(1) = 0; 
    end

    %% 6. POST-PROCESSING & RESIDUAL STRESS (Material Memory with Mixed Hardening)
    
    % A. Reconstruct Global History
    if num_segments > 0
        pts_per_seg = length(Segments(1).x_global);
        total_pts = num_segments * pts_per_seg;
        x_history = zeros(total_pts, 1);
        kappa_history = zeros(total_pts, 1);
        
        curr_idx = 1;
        for k = 1:num_segments
            x_history(curr_idx : curr_idx + pts_per_seg - 1) = Segments(k).x_global;
            kappa_history(curr_idx : curr_idx + pts_per_seg - 1) = Segments(k).Curvature;
            curr_idx = curr_idx + pts_per_seg;
        end
    else
        x_history = []; kappa_history = [];
    end
    
    % B. Stress Integration (Universal Return Mapping)
    stress_history = zeros(length(x_history), N_layers);
    plastic_profile = zeros(length(x_history), 1);
    yield_state_history = false(length(x_history), N_layers);

    
    % Recupera parametri modello (con fallback)
    if ~isfield(p, 'ModelType'), p.ModelType = 1; end % 1=Linear, 2=Ludwik, 3=Voce
    
    for i = 1:length(x_history)
        current_k = kappa_history(i);
        current_strain = -z_layers * (current_k - p.K0); % coil set added to the current curvature
        yield_count = 0;
        
        for z = 1:N_layers
            % 1. Calcolo Delta Strain
            if i == 1
                d_eps = current_strain(z);
            else
                prev_strain = -z_layers(z) * (kappa_history(i-1) - p.K0);
                d_eps = current_strain(z) - prev_strain;
            end
            
            % 2. Predittore Elastico (Trial)
            sigma_trial = sigma_current(z) + p.E * d_eps;
            
            % 3. Calcolo Raggio Isotropo Corrente (R) e Tangente Isotropo (H_iso_prime)
            ep = eps_pl_cum(z);
            
            if p.ModelType == 1 % Linear
                % H_iso passato come p.H_iso
                if ~isfield(p,'H_iso'), p.H_iso = 1000; end
                R_iso = p.H_iso * ep;
                H_iso_prime = p.H_iso;
                
            elseif p.ModelType == 2 % Ludwik: Sigma = Sy + K * eps^n
                if ~isfield(p,'K_hol'), p.K_hol = 500; end
                if ~isfield(p,'n_hol'), p.n_hol = 0.5; end
                % Evita divisione per zero
                eff_ep = max(ep, 1e-9);
                R_iso = p.K_hol * (eff_ep ^ p.n_hol);
                H_iso_prime = p.K_hol * p.n_hol * (eff_ep ^ (p.n_hol - 1));
                
            elseif p.ModelType == 3 % Voce: Sigma = S_sat - (S_sat-Sy)*exp(-b*ep)
                if ~isfield(p,'S_sat'), p.S_sat = 500; end
                if ~isfield(p,'b_voce'), p.b_voce = 10; end
                term = exp(-p.b_voce * ep);
                R_iso = (p.S_sat - p.Sy) * (1 - term);
                H_iso_prime = p.b_voce * (p.S_sat - p.Sy) * term;
            else
                R_iso = 0; H_iso_prime = 0;
            end
            
            Current_Radius = p.sig0 + R_iso;
            
            % 4. Verifica Snervamento (Yield Function)
            eta = sigma_trial - alpha_current(z); % Stress efficace relativo al centro
            f = abs(eta) - Current_Radius;
            
            if f <= 0
                % Passo Elastico
                sigma_current(z) = sigma_trial;
            else
                % Passo Plastico (Return Mapping)
                sgn = sign(eta);
                
                % Denominatore Consistente: E + H_kin + H_iso_prime
                denom = p.E + p.H_kin + H_iso_prime;
                
                d_lam = f / denom;
                
                % Update Variabili di Stato
                sigma_current(z) = sigma_trial - d_lam * p.E * sgn;
                alpha_current(z) = alpha_current(z) + p.H_kin * d_lam * sgn; % Sposta Centro
                eps_pl_cum(z)    = eps_pl_cum(z) + d_lam;                    % Espande Raggio
                
                yield_count = yield_count + 1;
                yield_state_history(i, z) = true;
            end
        end
        
        stress_history(i, :) = sigma_current';
        plastic_profile(i) = (yield_count / N_layers) * 100;
    end

    %% 6b. GEOMETRIC ELONGATION (CORREZIONE PLANARITÀ)
    % Calcola quanto si allunga la lamiera per seguire il percorso ondulato (Path Length)
    L_nominal = Xc(end) - Xc(1);
    L_actual = 0;
    
    for k = 1:length(Segments)
        % Lunghezza d'arco: dL = sqrt(1 + slope^2) * dx
        slopes = Segments(k).Slope;
        dx = Segments(k).s(2) - Segments(k).s(1); 
        
        % Somma lunghezze d'arco locali
        seg_len = sum(sqrt(1 + slopes.^2)) * dx;
        L_actual = L_actual + seg_len;
    end
    
    % Strain geometrico medio [%] causato dal percorso macchina
    Geometric_Elongation_Pct = (L_actual - L_nominal) / L_nominal * 100;

    %% 7. OUTPUTS
    Sigma_Exit = stress_history(end, :)';
    
    % Final Springback (from Exit Table state)
    I0 = (p.W * p.t^3)/12;
    M_End = sum(Sigma_Exit .* z_layers * dz * p.W);
    dK_End = M_End / (p.E * I0);
    
    K_Final = kappa_history(end) + dK_End;
    springback_stress = (M_End / I0) * z_layers;
    Sigma_Res = Sigma_Exit - springback_stress;
    
    % Roll Residuals (Virtual Unloading after each Real Roller)
    Roll_Residuals = zeros(N_layers, p.N);
    Yield_Rolls_Map = zeros(N_layers, p.N);

    for i = 1:p.N
        % 1. Target Uscita (per Stress Residuo)
        % Simula il taglio DOPO il rullo 
        x_exit = Xc_mach(i) + p.P/2; 
        [~, idx_ex] = min(abs(x_history - x_exit));
        
        Sig_Load = stress_history(idx_ex, :)';
        M_i = sum(Sig_Load .* z_layers * dz * p.W);
        dK_i = M_i / (p.E * I0);
        Roll_Residuals(:, i) = Sig_Load - p.E * z_layers * dK_i;

        % 2. Target Picco (per Visualizzazione Plasticità)
        % Cerchiamo lo stato SOTTO il rullo (dove il momento è massimo)
        x_center = Xc_mach(i);
        [~, idx_cen] = min(abs(x_history - x_center));
        
        % Salviamo la colonna: 1 se plastico, 0 se elastico
        Yield_Rolls_Map(:, i) = yield_state_history(idx_cen, :)';
    end

    %Estrazione Angoli di Contatto per l'App ---
    Contact_Angles_Rad = zeros(p.N, 1);
    for i = 1:p.N
        % Il segmento 'i' termina esattamente sul rullo 'i'
        Contact_Angles_Rad(i) = atan(Segments(i).Slope(end));
    end
    
    Metrics.Max_Stress = max(max(abs(stress_history)));
    Metrics.Max_Total_Stress = Metrics.Max_Stress;

    Metrics.Curvature = K_Final;
    Metrics.Residual_Stress_Surface = max(abs(Sigma_Res([1, end])));
    
    Data.x = x_history;
    Data.Kappa = kappa_history;
    Data.Sigma_Res = Sigma_Res;
    Data.z = z_layers;
    Data.Stress_History = stress_history;
    Data.Roll_Residuals = Roll_Residuals;
    Data.Yield_Rolls = Yield_Rolls_Map;
    Data.Segments = Segments;
    Data.Contact_Angles_Rad = Contact_Angles_Rad;
    Data.Plastic_Profile = plastic_profile;
    Data.Alpha_Final = alpha_current;
    Data.Eps_Pl_Final = eps_pl_cum;
    Data.Avg_Elongation_Pct = Geometric_Elongation_Pct;
    Data.Max_Total_Stress = Metrics.Max_Stress;
end