function Res = Leveler_Solver_3D(Sheet, MachineBase, Opts)
% LEVELER_SOLVER_3D 
% Motore fisico unificato. Esegue la simulazione completa della lamiera.
% Input:
%   Sheet: Struttura dati lamiera (.Geo, .Mat, .Defects)
%   MachineBase: Parametri macchina (N, P, R, I_in, I_out, Fc, Fl, etc.)
%   Opts: Opzioni simulazione (.nStrips, .GridX, .GridY)
% Output:
%   Res: Struttura risultati completa pronta per la visualizzazione/export

    %% 1. SETUP GEOMETRICO
    W = Sheet.Geo.W;
    nStrips = Opts.nStrips;
    y_strips = linspace(-W/2, W/2, nStrips);
    
    % Vettori accumulatori
    vals_len_mach = zeros(1, nStrips); % Lunghezza arco macchina
    vals_curv_res = zeros(1, nStrips); % Curvatura residua
    vals_stress   = zeros(1, nStrips); % Stress residuo surf
    vals_plast    = zeros(1, nStrips); % % Plastica
    StripData     = cell(1, nStrips);  % Dati dettagliati per debug/click
    any_break     = false;

    %% 2. CALCOLO STRAIN INGRESSO (Geometria Difetto)
    % Ricostruiamo la mappa di strain iniziale basata su H e L
    if Sheet.Defects.L_mm > 0
        Eps_Max_In_Pct = (pi^2 * Sheet.Defects.H_mm^2) / (4 * Sheet.Defects.L_mm^2) * 100;
    else
        Eps_Max_In_Pct = 0;
    end
    
    % Profilo trasversale (Shape function)
    y_norm_sq = (2 * y_strips / W).^2;
    waveType = 'Edge Waves';
    if isfield(Sheet.Defects, 'WaveType'), waveType = Sheet.Defects.WaveType; end

    if strcmpi(waveType, 'Edge Waves')
        prof_in = y_norm_sq; 
    elseif strcmpi(waveType, 'Center Buckles')
        prof_in = 1 - y_norm_sq;
    else
        prof_in = abs(y_norm_sq - 0.5);
    end
    
    Vec_Strain_In = Eps_Max_In_Pct * prof_in; % [%]

    %% 3. SIMULAZIONE MACCHINA (Loop Strisce)
    % Calcoliamo come la macchina deforma ogni singola fibra
    
    for s = 1:nStrips
        % Clona parametri base
        p = MachineBase;
        p.y_coord = y_strips(s);
        
        % Inietta parametri materiale
        p.t = Sheet.Geo.t; p.W = Sheet.Geo.W;
        p.E = Sheet.Mat.E; p.Sy = Sheet.Mat.Sy; p.sig0 = Sheet.Mat.Sy;
        p.H_kin = Sheet.Mat.H_kin;
        
        % Inietta geometria locale input (Solo curvatura longitudinale)
        % NOTA: Non iniettiamo l'onda come K0 variabile qui, perché gestiamo
        % l'onda come differenza di lunghezza (Strain Balance) alla fine.
        p.K0 = Sheet.Defects.K0_Geo;
        
        % Esegui Kernel
        [res_s, data_s] = Leveler_Kernel_CIM(p);
        
        % A. Estrarre Lunghezza d'Arco Reale (Path Length)
        % Questo cattura l'effetto di Fc/Fl (percorso più lungo al centro)
        L_arc = 0;
        if isfield(data_s, 'Segments')
            for kSeg = 1:length(data_s.Segments)
                slopes = data_s.Segments(kSeg).Slope;
                dx = data_s.Segments(kSeg).s(2) - data_s.Segments(kSeg).s(1);
                L_arc = L_arc + sum(sqrt(1 + slopes.^2)) * dx;
            end
        end
        vals_len_mach(s) = L_arc;
        
        % B. Estrarre altri dati
        vals_curv_res(s) = res_s.Curvature;
        vals_stress(s)   = res_s.Residual_Stress_Surface;
        
        % Media allungamento plastico puro (per diagnostica)
        if isfield(data_s, 'Plastic_Profile')
            vals_plast(s) = mean(data_s.Plastic_Profile);
        end
        
        % Check rottura
        if isfield(res_s, 'Max_Total_Stress') && isfield(Sheet.Mat, 'Rm') 
            if res_s.Max_Total_Stress > Sheet.Mat.Rm, any_break = true; end
        end
        
        % Salvataggio dati completi per UI (Popup)
        data_s.p = p; % Salva params usati
        StripData{s} = data_s;
    end

    %% 4. BILANCIO PLANARITÀ (Strain Balance Method)
    
    % A. Strain Geometrico Macchina [%]
    % Calcolato rispetto alla fibra che ha fatto il percorso più breve (Rif.)
    L_ref = min(vals_len_mach);
    if L_ref == 0, L_ref = 1; end
    
    % Quanto la macchina ha "stirato" geometricamente ogni fibra in più rispetto alla minima
    Vec_Strain_Mach = (vals_len_mach - L_ref) / L_ref * 100; 
    
    % Aggiungiamo anche la componente plastica media (stiramento materiale)
    % Vec_Strain_Mach = Vec_Strain_Mach + vals_plast; % (Opzionale, spesso domina la geometrica)

    % B. Strain Totale Residuo
    % Difetto Ingresso + Azione Macchina
    Vec_Strain_Tot = Vec_Strain_In + Vec_Strain_Mach;
    
    % C. Calcolo I-Units Finali
    % La planarità è la differenza tra max e min strain residuo
    Delta_Strain_Res = max(Vec_Strain_Tot) - min(Vec_Strain_Tot); % [%]
    Res.Flatness_I_Units = (Delta_Strain_Res / 100) * 1e5;
    
    % D. Ricostruzione Onda Residua (H_out)
    L_out = Sheet.Defects.L_mm; if L_out<=0, L_out=500; end
    Res.H_mm_Res = (2 * L_out / pi) * sqrt(Delta_Strain_Res / 100);
    
    %% 5. BILANCIO CROSSBOW (Effetto Poisson)
    % K_trans_out = K_trans_in - nu * K_long_res_avg
    nu = 0.3;
    Avg_K_Long = mean(vals_curv_res);
    Res.Crossbow_Res = Sheet.Defects.K_Trans_Geo - (nu * Avg_K_Long);
    
    %% 6. OUTPUT PER MAPPE (Interpolazione Griglia)
    % Interpoliamo i risultati 1D (stisce) sulla griglia 2D richiesta dall'App
    
    [GridX, GridY] = meshgrid(Opts.GridX, Opts.GridY);
    
    % Creiamo interpolanti
    F_Stress = griddedInterpolant(y_strips, vals_stress, 'linear', 'nearest');
    F_Curv   = griddedInterpolant(y_strips, vals_curv_res, 'linear', 'nearest');
    
    % Mappe 2D (Costanti su X, variabili su Y)
    % Nota: In realtà variano anche su X se facciamo ottimizzazione locale, 
    % ma per la "Mappa Risultato" di una configurazione fissa, variano solo su Y.
    Res.Map.Stress = repmat(F_Stress(Opts.GridY)', 1, length(Opts.GridX))'; 
    Res.Map.Curv   = repmat(F_Curv(Opts.GridY)', 1, length(Opts.GridX))';
    
    % Planarità e Crossbow sono valori scalari globali per questa configurazione,
    % ma per le mappe a colori ("Sensitivity Map") l'App ricalcolerà punti diversi.
    % Qui restituiamo i valori scalari della configurazione corrente.
    Res.Scalar.Stress = mean(vals_stress);
    Res.Scalar.Curv   = Avg_K_Long;
    Res.Scalar.Flatness = Res.Flatness_I_Units;
    Res.Scalar.Crossbow = Res.Crossbow_Res;
    Res.Scalar.Fail = any_break;
    
    Res.StripData = StripData;
    Res.StripY = y_strips;
    
    % Dati diagnostici per grafico 3D
    Res.Viz.H_Profile = (2 * L_out / pi) * sqrt((Vec_Strain_Tot - min(Vec_Strain_Tot))/100);
    Res.Viz.K_Profile = vals_curv_res;
end