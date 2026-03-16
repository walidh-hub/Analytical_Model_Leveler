classdef LevelerApp < matlab.apps.AppBase

    % Properties (Componenti Interfaccia)
    properties (Access = public)
        UIFigure             matlab.ui.Figure
        GridLayoutMain       matlab.ui.container.GridLayout
        LeftSidebar          matlab.ui.container.Panel
        DashboardGrid        matlab.ui.container.GridLayout

        % Inputs
        Edit_N, Edit_P, Edit_R
        Edit_I_in, Edit_I_out
        Edit_Fc, Edit_Fl %flessi dei controrulli
        Edit_CoilRad        matlab.ui.control.NumericEditField

        % --- ANALISI ---
        Drop_AxisX, Edit_MinX, Edit_MaxX
        Drop_AxisY, Edit_MinY, Edit_MaxY
        Drop_OptMode

        % Componenti Nuovi
        Slider_Width         matlab.ui.control.Slider
        Lbl_SliderVal        matlab.ui.control.Label

        % Dati Cache per lo Slider
        StripResultsData     % Cell array che contiene i risultati di N strisce
        StripYCoords         % Vettore delle coordinate Y corrispondenti

        % Aggiungiamo un 4° asse per lo Stress Residuo (Thickness)
        Ax_ResStressProfile  matlab.ui.control.UIAxes

        % Buttons
        Btn_Run, Btn_ShowMat, Btn_ShowStress, Btn_ShowHysteresis, Btn_Show3D
        Btn_LoadSheet, Btn_ExportRes

        % Axes
        Ax_Machine, Ax_Curvature, Ax_Plastic, Ax_StressMap, Ax_CurvMap, Ax_CrossbowMap, Ax_FlatnessMap

        % Dati
        GridResults, VarMap, CurrentDetailData
        CurrentSheetData % <--- NUOVO: Contiene tutta la struttura caricata dal .sheet
        Lbl_SheetInfo    % <--- NUOVO: Mostra info riassuntive del file caricato
        SimulationResults

        % Export
        Btn_Save, Btn_Load
        Btn_ShowInitial

    end

    methods (Access = private)

        % --- CALCOLO ---

        function prepareAnalysis(app)
            % Controllo preliminare
            if isempty(app.CurrentSheetData)
                uialert(app.UIFigure, 'You must updload a sheet (.sheet) to simulate!', 'Missing Data');
                return;
            end

            % Crea una piccola finestra di dialogo modale
            d = uifigure('Name', 'Simulation parameters', 'Position', [500 400 350 300]);
            gl = uigridlayout(d, [6, 2]);

            uilabel(gl, 'Text', 'Analysis Mode:');
            modeDrop = uidropdown(gl, 'Items', {'Singola Striscia (Veloce)', 'Multi-Strip (3D)'});

            uilabel(gl, 'Text', 'Width disctetization:');
            stripEdit = uieditfield(gl, 'numeric', 'Value', 11);

            uilabel(gl, 'Text', 'Grid points:');
            gridEdit = uieditfield(gl, 'numeric', 'Value', 5);

            uilabel(gl, 'Text', 'Fitter iteractions:');
            fitEdit = uieditfield(gl, 'numeric', 'Value', 2);

            % Creiamo prima il bottone, poi assegniamo il layout
            btnStart = uibutton(gl, 'Text', 'Go to Simulation', ...
                'ButtonPushedFcn', @(s,e) start(app, d, modeDrop.Value, stripEdit.Value, gridEdit.Value, fitEdit.Value));

            % Posizionamento nella griglia (Riga 6, esteso su entrambe le colonne)
            btnStart.Layout.Row = 6;
            btnStart.Layout.Column = [1 2];

            function start(app, diag, mode, nStrips, nGrid, nFit)
                delete(diag); % Chiude il popup
                % Passa i parametri alla funzione di calcolo
                app.runAnalysis(mode, nStrips, nGrid, nFit);
            end
        end

        % function runAnalysis(app, mode, nStrips, nGrid, nFit)
        %     % 1. Input Base
        %     base.N = app.Edit_N.Value; base.P = app.Edit_P.Value; base.R = app.Edit_R.Value;
        %     base.I_in = app.Edit_I_in.Value; base.I_out = app.Edit_I_out.Value;
        %     base.Fc = app.Edit_Fc.Value; base.Fl = app.Edit_Fl.Value;
        % 
        %     % 2. Recupera Dati Lamiera (da Struttura Caricata)
        %     S = app.CurrentSheetData;
        %     base.t = S.Geo.t;
        %     base.W = S.Geo.W;
        %     base.E = S.Mat.E;
        %     base.Sy = S.Mat.Sy;
        %     base.sig0 = base.Sy;
        %     base.H_kin = S.Mat.H_kin;
        %     base.K0 = S.Defects.K0_Geo;
        %     base.K_crossbow = S.Defects.K_Trans_Geo; % Idem [1/m]
        %     base.H_mm = S.Defects.H_mm;
        %     base.L_mm = S.Defects.L_mm;
        %     base.Initial_Eps_Pl = S.State.Eps_Pl_Final;
        %     base.Initial_Sigma = S.State.Sigma_Res;
        % 
        %     if isfield(S.Defects, 'WaveType')
        %         base.WaveType = S.Defects.WaveType;
        %     else
        %         base.WaveType = 'Edge Waves';
        %     end
        % 
        %     % Rm check (Se non presente, stima safe)
        %     if isfield(S.Mat, 'Rm'), base.Rm = S.Mat.Rm; else, base.Rm = base.Sy * 1.5; end
        % 
        %     % Gestione Memoria Plastica (Multi-Pass)
        %     if isfield(S, 'State') && isfield(S.State, 'Alpha_Final')
        %         base.Initial_Alpha = S.State.Alpha_Final;
        %         disp('Simulazione Multi-Pass: Caricata memoria plastica (Backstress).');
        %     end
        % 
        %     % Gestione Modello Materiale
        %     modMap = containers.Map({'Linear','Ludwik','Voce'}, {1, 2, 3});
        %     if isKey(modMap, S.Mat.Model)
        %         base.ModelType = modMap(S.Mat.Model);
        %     else
        %         base.ModelType = 1; % Fallback
        %     end
        % 
        %     % Parametri specifici (Mapping generico P1/P2)
        %     if base.ModelType == 1, base.H_iso = S.Mat.P1;
        %     elseif base.ModelType == 2, base.K_hol = S.Mat.P1; base.n_hol = S.Mat.P2;
        %     elseif base.ModelType == 3, base.S_sat = S.Mat.P1; base.b_voce = S.Mat.P2;
        %     end
        % 
        %     % Nota: base.WaveAmp è ridondante se il Kernel usa H e L, % ma lo lasciamo per compatibilità se serve visualizzarlo
        %     % WaveAmp (Strain) serve al Kernel per fallback o calcoli rapidi?  % Lo ricalcoliamo coerentemente da H e L per non avere discrepanze.
        %     % Calcolo I-Units per Kernel
        %     if base.L_mm > 0
        %         base.WaveAmp = (base.H_mm / base.L_mm)^2 * 246760;
        %     else
        %         base.WaveAmp = 0;
        %     end
        % 
        % 
        %     % 2. Setup Griglia
        %     field_x = app.VarMap{strcmp(app.VarMap(:,1), app.Drop_AxisX.Value), 2};
        %     field_y = app.VarMap{strcmp(app.VarMap(:,1), app.Drop_AxisY.Value), 2};
        %     range_x = linspace(app.Edit_MinX.Value, app.Edit_MaxX.Value, nGrid);
        %     range_y = linspace(app.Edit_MinY.Value, app.Edit_MaxY.Value, nGrid);
        % 
        %     [GRID_X, GRID_Y] = meshgrid(range_x, range_y);
        %     app.GridResults = struct();
        %     app.GridResults.FlatnessError = zeros(size(GRID_X));
        %     RES_STRESS = zeros(size(GRID_X)); RES_CURV = zeros(size(GRID_X)); RES_XBOW = zeros(size(GRID_X));
        %     FAIL_MASK = false(size(GRID_X));
        % 
        % 
        %     % Vecchio codice prima di integrazione bucling e edgewave
        %     % y_norm_sq = (2 * y_strips / base.W).^2;
        %     % if strcmpi(base.WaveType, 'Edge Waves')
        %     %     profile_y = y_norm_sq;         % Difetto massimo ai bordi
        %     % elseif strcmpi(base.WaveType, 'Center Buckles')
        %     %     profile_y = (1 - y_norm_sq);   % Difetto massimo al centro
        %     % else
        %     %     profile_y = (y_norm_sq - 0.5); % Bilanciato
        %     % end
        % 
        %     % Parametri Analisi
        %     %is3D = strcmp(mode, 'Multi-Strip (3D)');
        %     %y_strips = linspace(-base.W/2, base.W/2, nStrips);
        % 
        %     d = uiprogressdlg(app.UIFigure, 'Title', 'Simulation Log...', 'Message', '--- Inizio Sessione ---', 'Cancelable', 'off');
        % 
        %     try
        %         isFastMode = strcmp(mode, 'Singola Striscia (Veloce)');
        % 
        %         if isFastMode
        %             % In modalità veloce, calcoliamo solo il punto centrale della griglia
        %             mid_idx = ceil(numel(GRID_X)/2);
        %             loop_indices = mid_idx;
        %             d.Message = 'Modalità Veloce: Calcolo punto singolo...';
        %             d.Indeterminate = 'on'; 
        %         else
        %             % In modalità 3D, calcoliamo tutta la mappa (100 punti)
        %             loop_indices = 1:numel(GRID_X);
        %             d.Message = 'Generazione Mappa Completa...';
        %             d.Indeterminate = 'off';
        %         end
        % 
        % 
        %         total = numel(GRID_X);
        % 
        %         OptsMap.nStrips = 5; % Bastano 5 strisce per stimare la tendenza sulla mappa
        %         OptsMap.GridX = []; OptsMap.GridY = []; % Non serve interpolazione qui
        % 
        %         for k = 1:total
        %             if mod(k,5)==0, d.Value = k/(total*1.2); end
        % 
        %             % Aggiorna parametri macchina per questo punto della griglia
        %             p_curr = base;
        %             p_curr = app.updatePStruct(p_curr, field_x, GRID_X(k));
        %             p_curr = app.updatePStruct(p_curr, field_y, GRID_Y(k));
        % 
        % 
        % 
        %             % --- CALCOLO MULTI-STRISCIA LOCALE (Sostituisce Solver_3D) ---
        %             n_test = 5; % Numero di strisce per la mappa (veloce)
        %             y_test = linspace(-p_curr.W/2, p_curr.W/2, n_test);
        %             elongations = zeros(1, n_test);
        %             curvatures = zeros(1, n_test);
        % 
        %             for s = 1:n_test
        %                 ps = p_curr;
        %                 % Calcolo K0 locale (Coil Set + Contributo Onde)
        %                 y_norm = (2 * y_test(s) / ps.W)^2;
        %                 if strcmpi(ps.WaveType, 'Center Buckles'), prof = 1 - y_norm;
        %                 elseif strcmpi(ps.WaveType, 'Balanced'), prof = abs(y_norm - 0.5);
        %                 else, prof = y_norm; end
        % 
        %                 % K_wave [1/mm] derivata dalla planarità di input
        %                 K_wave = (ps.WaveAmp / 246760) * prof; 
        %                 ps.K0 = base.K0 + K_wave;
        %                 ps.y_coord = y_test(s);
        % 
        %                 [M, ~] = Leveler_Kernel_CIM(ps);
        %                 elongations(s) = M.Avg_Elongation_Pct;
        %                 curvatures(s) = M.Curvature;
        %             end
        % 
        %             % Calcolo Scalari per la Mappa
        %             app.GridResults.FlatnessError(k) = (max(elongations) - min(elongations)) * 1000; % I-Units
        %             app.GridResults.S(k) = M.Residual_Stress_Surface;
        %             app.GridResults.C(k) = mean(curvatures);
        %         end
        % 
        %             % Salvataggio Risultati Scalari nelle Matrici della Mappa
        %             app.GridResults.FlatnessError(k) = Res.Scalar.Flatness;
        %             RES_STRESS(k) = Res.Scalar.Stress;
        %             RES_CURV(k)   = Res.Scalar.Curv;
        %             RES_XBOW(k)   = Res.Scalar.Crossbow;
        %             FAIL_MASK(k)  = Res.Scalar.Fail;
        % 
        %             % Salvataggio Risultati
        %             app.GridResults.X = GRID_X; app.GridResults.Y = GRID_Y;
        %             app.GridResults.S = RES_STRESS; app.GridResults.C = RES_CURV; app.GridResults.XB = RES_XBOW;
        %             app.GridResults.Fail = FAIL_MASK;
        %             app.GridResults.Base = base; app.GridResults.FieldX = field_x; app.GridResults.FieldY = field_y;
        % 
        %             % --- OTTIMIZZAZIONE (Fitter) ---
        %             target_mode = app.Drop_OptMode.Value;
        % 
        %             % Selezione Mappa Obiettivo (per trovare il punto di partenza)
        %             if strcmp(target_mode, 'RES STRESS')
        %                 TARGET_MAP = RES_STRESS;
        %             elseif strcmp(target_mode, 'Curvature')
        %                 TARGET_MAP = abs(RES_CURV);
        %             elseif strcmp(target_mode, 'Flatness (I-Units)')
        %                 TARGET_MAP = app.GridResults.FlatnessError;
        %             else
        %                 % Caso Crossbow
        %                 TARGET_MAP = abs(app.GridResults.XB);
        %             end
        % 
        %             [current_min, idx] = min(TARGET_MAP(:));
        %             best_x = GRID_X(idx); best_y = GRID_Y(idx);
        % 
        %             d.Message = ['Ottimizzazione (' target_mode ')...'];
        %             msg = sprintf('Calcolo punto mappa %d di %d...', k, total);
        %             d.Message = sprintf('%s\n%s', d.Message, msg); % Accumula nel log
        %             FIT_X = zeros(nFit, 1);
        %             FIT_Y = zeros(nFit, 1);
        %             step_x = (max(range_x)-min(range_x))/10; step_y = (max(range_y)-min(range_y))/10;
        % 
        %             for iter = 1:nFit
        % 
        %                 msg = sprintf('[%s] Punto %d/%d - Iterazione %d/%d...', target_mode, k, total, iter, nFit);
        %                 d.Message = sprintf('%s\n%s', d.Message, msg); % Accumula nel log
        % 
        %                 found_better = false;
        %                 % Definiamo i vicini (aggiungiamo Fc e Fl se necessario)
        %                 nb = [best_x+step_x, best_y; best_x-step_x, best_y; best_x, best_y+step_y; best_x, best_y-step_y];
        % 
        %                 for n = 1:4
        %                     cx = nb(n,1); cy = nb(n,2);
        %                     if cx<min(range_x)||cx>max(range_x)||cy<min(range_y)||cy>max(range_y), continue; end
        % 
        %                     p = base; p = app.updatePStruct(p, field_x, cx); p = app.updatePStruct(p, field_y, cy);
        % 
        %                     % Setup rapido per il Fitter
        %                     OptsFit.nStrips = 3; % Bastano 3 strisce (Centro/Bordi) per capire la direzione
        %                     OptsFit.GridX = []; OptsFit.GridY = [];
        % 
        %                     ResFit = Leveler_Solver_3D(S, p, OptsFit);
        % 
        %                     % Selezione Obiettivo da Minimizzare
        %                     if strcmp(target_mode, 'Flatness (I-Units)')
        %                         val = ResFit.Scalar.Flatness;
        %                     elseif strcmp(target_mode, 'RES STRESS')
        %                         val = abs(ResFit.Scalar.Stress);
        %                     elseif strcmp(target_mode, 'Curvature')
        %                         val = abs(ResFit.Scalar.Curv);
        %                     else % Crossbow
        %                         val = abs(ResFit.Scalar.Crossbow);
        %                     end
        % 
        %                     if val < current_min
        %                         current_min = val; best_x = cx; best_y = cy; found_better = true;
        %                     end
        %                 end
        % 
        %                 % Assegnazione diretta (Veloce)
        %                 FIT_X(iter) = best_x;
        %                 FIT_Y(iter) = best_y;
        % 
        %                 if ~found_better
        %                     step_x = step_x / 2;
        %                     step_y = step_y / 2;
        %                 end
        %                 if iter > 2 && step_x < 1e-4, break; end
        %             end
        % 
        %             app.GridResults.FitPathX = FIT_X; app.GridResults.FitPathY = FIT_Y;
        %         end
        %     catch ME
        %         %close(d);
        %         uialert(app.UIFigure, ME.message, 'Errore'); return;
        %     end
        %     %close(d);
        %     d.Message = sprintf('%s\n\n>>> CALCOLO TERMINATO', d.Message);
        %     d.Value = 1;
        % 
        %     app.updateDetailPlots(best_x, best_y, true);
        %     app.Btn_ShowMat.Enable = 'on'; app.Btn_ShowStress.Enable = 'on';
        %     app.Btn_ShowHysteresis.Enable = 'on'; app.Btn_Show3D.Enable = 'on'; app.Btn_Save.Enable = 'on';
        % end



        function runAnalysis(app, mode, nStrips, nGrid, nFit)
            % --- FASE 1: DATA EXTRACTION & MATERIAL MAPPING ---
            
            % 1. Parametri Macchina (da UI)
            base.N    = round(app.Edit_N.Value);
            base.P    = app.Edit_P.Value;
            base.R    = app.Edit_R.Value;
            base.I_in = app.Edit_I_in.Value;
            base.I_out = app.Edit_I_out.Value;
            base.Fc   = app.Edit_Fc.Value;
            base.Fl   = app.Edit_Fl.Value;

            % 2. Dati Lamiera (dal file .sheet caricato)
            S = app.CurrentSheetData;
            base.t      = S.Geo.t;
            base.W      = S.Geo.W;
            base.E      = S.Mat.E;
            base.Sy     = S.Mat.Sy;
            base.sig0   = base.Sy; % Alias per il raggio iniziale del Kernel
            base.H_kin  = S.Mat.H_kin;
            base.Rm     = S.Mat.Rm;

            % 3. Mappatura Modello di Incrudimento
            % Convertiamo il nome del modello in ID numerico per il Kernel (1, 2, 3)
            modMap = containers.Map({'Linear','Ludwik','Voce'}, {1, 2, 3});
            if isKey(modMap, S.Mat.Model)
                base.ModelType = modMap(S.Mat.Model);
            else
                base.ModelType = 1; % Fallback cautelativo
            end

            % Assegnazione parametri P1/P2 in base al modello
            if base.ModelType == 1
                base.H_iso = S.Mat.P1; % Lineare
            elseif base.ModelType == 2
                base.K_hol = S.Mat.P1; base.n_hol = S.Mat.P2; % Ludwik
            elseif base.ModelType == 3
                base.S_sat = S.Mat.P1; base.b_voce = S.Mat.P2; % Voce
            end

            % 4. Configurazione Difetti di Input
            base.K0 = S.Defects.K0_Geo;
            if isfield(S.Defects, 'WaveType'), base.WaveType = S.Defects.WaveType;
            else, base.WaveType = 'Edge Waves'; end % Default

            % 5. Memoria Plastica (Supporto Multi-Pass)
            % Se il file .sheet contiene stati finali, li usiamo come punto di partenza
            base.Initial_Alpha  = S.State.Alpha_Final; % Backstress
            base.Initial_Sigma  = S.State.Sigma_Res;   % Stress residuo
            base.Initial_Eps_Pl = S.State.Eps_Pl_Final; % Deformazione plastica cumulata


            % --- FASE 2: SENSITIVITY GRID SETUP ---

            % 1. Identificazione dei campi da variare (Mappatura tramite VarMap)
            % Determiniamo i nomi interni dei campi (es. 'I_in', 'Fc') basandoci sulla scelta nei dropdown
            field_x = app.VarMap{strcmp(app.VarMap(:,1), app.Drop_AxisX.Value), 2};
            field_y = app.VarMap{strcmp(app.VarMap(:,1), app.Drop_AxisY.Value), 2};

            % 2. Generazione dei Range Lineari
            range_x = linspace(app.Edit_MinX.Value, app.Edit_MaxX.Value, nGrid);
            range_y = linspace(app.Edit_MinY.Value, app.Edit_MaxY.Value, nGrid);

            % 3. Creazione della Griglia 2D (Meshgrid)
            [GRID_X, GRID_Y] = meshgrid(range_x, range_y);

            % 4. Inizializzazione della Struttura GridResults
            app.GridResults = struct();
            app.GridResults.X = GRID_X;
            app.GridResults.Y = GRID_Y;
            app.GridResults.FieldX = field_x;
            app.GridResults.FieldY = field_y;
            app.GridResults.Base = base; % Salviamo lo stato iniziale per i plot di dettaglio

            % 5. Preallocazione Matrici per Performance
            % Inizializziamo a zero o falso per evitare errori di dimensione durante il loop
            app.GridResults.FlatnessError = zeros(size(GRID_X)); % Errore di planarità
            app.GridResults.S    = zeros(size(GRID_X));          % Stress Residuo
            app.GridResults.C    = zeros(size(GRID_X));          % Curvatura Residua
            app.GridResults.Fail = false(size(GRID_X));          % Maschera di Rottura

            % Setup Barra di Progresso
            d = uiprogressdlg(app.UIFigure, 'Title', 'Simulation Log...', ...
                'Message', 'Generazione Mappa...', 'Indeterminate', 'off');

            % --- FASE 3: CORE SIMULATION LOOP (SINGLE STRIP) ---
            
            try
                total = numel(GRID_X);
                % Struttura temporanea per raccogliere i dati grezzi del Kernel
                % Verranno elaborati nella Fase 4 per estrarre failure e metriche
                raw_M = cell(size(GRID_X)); 
                raw_D = cell(size(GRID_X));

                for k = 1:total
                    % 1. Aggiornamento UI (Progress Bar)
                    if mod(k, 5) == 0
                        d.Value = k / total;
                        d.Message = sprintf('Simulazione punto %d di %d...', k, total);
                    end

                    % 2. Preparazione parametri per il punto corrente
                    p_curr = base;
                    % updatePStruct inserisce dinamicamente i valori della griglia (es. I_in, Fc, ecc.)
                    p_curr = app.updatePStruct(p_curr, field_x, GRID_X(k));
                    p_curr = app.updatePStruct(p_curr, field_y, GRID_Y(k));
                    
                    % 3. Configurazione "Singola Striscia"
                    % Per ora analizziamo solo l'asse neutro/centrale della lamiera
                    p_curr.y_coord = 0; 

                    % 4. ESECUZIONE KERNEL CIM
                    % Chiamata al motore fisico per risolvere la geometria e lo stress
                    [M, D] = Leveler_Kernel_CIM(p_curr); 

                    % 5. Archiviazione temporanea dei risultati grezzi
                    raw_M{k} = M;
                    raw_D{k} = D;
                end

                % --- FASE 4: FAILURE & METRICS EXTRACTION ---
            
            for k = 1:total
                % Recuperiamo i risultati della simulazione per il punto k
                M = raw_M{k}; 
                
                % 1. Estrazione Curvatura Residua [1/m]
                % Il Kernel calcola la curvatura finale post-molleggio.
                % Convertiamo da 1/mm a 1/m per una lettura standard nelle mappe.
                app.GridResults.C(k) = M.Curvature * 1000; 

                % 2. Estrazione Stress Residuo Superficiale [MPa]
                % Rappresenta lo stress massimo presente sulla pelle della lamiera.
                app.GridResults.S(k) = M.Residual_Stress_Surface;

                % 3. Verifica Integrità (Fail Mask)
                % Confrontiamo lo stress massimo raggiunto durante tutto il processo 
                % con il carico di rottura (Rm) definito nel materiale.
                if isfield(M, 'Max_Total_Stress')
                    app.GridResults.Fail(k) = M.Max_Total_Stress > base.Rm;
                end

                % 4. Nota sulla Planarità (Single Strip)
                % In modalità "Singola Striscia", l'errore di planarità locale 
                % rispetto alla media è nullo. Questo campo verrà popolato 
                % correttamente solo nelle analisi Multi-Strip.
                app.GridResults.FlatnessError(k) = 0; 
            end

            % --- FASE 5: MAPPING & RESULT STORAGE ---
            
            % 1. Salvataggio Metadati per il Plotting
            % Memorizziamo quali variabili sono state usate per gli assi X e Y, 
            % così i grafici sapranno aggiornare automaticamente le etichette.
            app.GridResults.FieldX = field_x;
            app.GridResults.FieldY = field_y;

            % 2. Selezione dell'Obiettivo di Ottimizzazione
            % Identifichiamo quale mappa utilizzare per trovare il setup ottimale 
            % in base alla scelta effettuata dall'utente nel dropdown.
            target_mode = app.Drop_OptMode.Value;
            if strcmp(target_mode, 'RES STRESS')
                TARGET_MAP = app.GridResults.S;
            elseif strcmp(target_mode, 'Curvature')
                TARGET_MAP = abs(app.GridResults.C);
            else
                TARGET_MAP = app.GridResults.FlatnessError;
            end

            % 3. Identificazione del Punto "Migliore" sulla Mappa
            % Troviamo le coordinate (X, Y) del punto che minimizza l'obiettivo scelto.
            [~, idx_opt] = min(TARGET_MAP(:));
            best_x = GRID_X(idx_opt);
            best_y = GRID_Y(idx_opt);

            % 4. Sblocco dei Pulsanti di Analisi
            % Ora che i dati sono pronti, abilitiamo l'accesso ai dettagli dello stress e del 3D.
            app.Btn_ShowStress.Enable = 'on';
            app.Btn_ShowHysteresis.Enable = 'on';
            app.Btn_Show3D.Enable = 'on';
            app.Btn_ExportRes.Enable = 'on';

            % 5. Chiusura della Barra di Progresso
            d.Value = 1;

            % --- FASE 6: REFRESH DASHBOARD ---

            % 1. Aggiornamento Messaggio (PRIMA di chiudere)
            d.Message = 'Analysis complete! Displaying optimal point...';
            d.Value = 1;

            % 2. Aggiornamento Grafici
            app.updateDetailPlots(best_x, best_y, true); 

            % 3. ORA possiamo chiudere la barra
            close(d);

            catch ME
                if isvalid(d), close(d); end
                uialert(app.UIFigure, ME.message, 'Errore');
            end 
            
            % Cleanup finale di sicurezza
            if exist('d','var') && isvalid(d), close(d); end 
        end 


        function p = updatePStruct(~, p, field, val)
            p.(field) = val;
            if strcmp(field, 'N'), p.N = round(val); end
            % Aggiungiamo Fc e Fl per il Fitter
            if strcmp(field, 'Fc'), p.Fc = val; end
            if strcmp(field, 'Fl'), p.Fl = val; end
        end

        % --- DASHBOARD ---
        function updateDetailPlots(app, sel_x, sel_y, isOptimized)
            if nargin < 4, isOptimized = false; end
            if isempty(app.GridResults), return; end
            res = app.GridResults;

            % 1. Recupera la struttura base PRIMA di tutto
            p = res.Base;

            % Funzione annidata per i contour plot
            function safe_contour(ax, Z, title_s)
                cla(ax);
                min_z = min(Z(:)); max_z = max(Z(:));
                delta = max_z - min_z;

                hold(ax, 'on');
                if delta < 1e-9
                    [~, h] = contourf(ax, res.X, res.Y, Z, [min_z-0.01, min_z+0.01]);
                else
                    [~, h] = contourf(ax, res.X, res.Y, Z, 100, 'LineStyle', 'none');
                end

                row = dataTipTextRow('Valore:', Z); % Crea la riga con i dati di Z
                h.DataTipTemplate.DataTipRows(end+1) = row; % La aggiunge all'etichetta

                colormap(ax, 'jet'); colorbar(ax);

                % Grid Points
                plot(ax, res.X(:), res.Y(:), 'k.', 'MarkerSize', 4, 'HitTest','off');

                % Punti Fitter
                if isfield(res, 'FitPathX') && ~isempty(res.FitPathX)
                    plot(ax, res.FitPathX, res.FitPathY, 'w.', 'MarkerSize', 8, 'HitTest', 'off');
                end

                % Punti Rottura
                if isfield(res, 'Fail') && any(res.Fail(:))
                    plot(ax, res.X(res.Fail), res.Y(res.Fail), 'kx', 'MarkerSize', 10, 'LineWidth', 2, 'HitTest', 'off');
                end

                % Punto Selezionato
                color = 'r'; if isOptimized, color = 'g'; end
                plot(ax, sel_x, sel_y, 'wp', 'MarkerSize', 14, 'MarkerFaceColor', color);

                hold(ax, 'off'); ax.Title.String = title_s;
            end

            % Disegna le Mappe
            safe_contour(app.Ax_StressMap, res.S, 'Residual stress [MPa]');
            safe_contour(app.Ax_CurvMap, abs(res.C), 'Curvature [1/m]');
            %safe_contour(app.Ax_FlatnessMap, res.FlatnessError, 'Planarity [I-Units]');
            %safe_contour(app.Ax_CrossbowMap, res.XB * 1000, 'Crossbow [1/m]');

            % 2. Aggiorna p con i valori del punto selezionato (X, Y)
            p = app.updatePStruct(p, res.FieldX, sel_x);
            p = app.updatePStruct(p, res.FieldY, sel_y);

            n_slices = 11; % Numero dispari per avere il centro esatto
            y_slices = linspace(-p.W/2, p.W/2, n_slices);

            % 3. Calcola Dettagli per il punto selezionato
            [M, D] = Leveler_Kernel_CIM(p);
            D.Curvature = M.Curvature;
            D.Residual_Stress_Surface = M.Residual_Stress_Surface;
            D.Max_Total_Stress = M.Max_Total_Stress;
            D.p = p;

            % --- ADAPTER: Compatibilità CIM -> App ---
            % 1. Alias per la curvatura (App usa Kappa_Geo, CIM usa Kappa)
            if ~isfield(D, 'Kappa_Geo'), D.Kappa_Geo = D.Kappa; end

            % 2. Trasponi la Storia degli Stress (CIM: Time x Layers, App: Layers x Time)
            if isfield(D, 'Stress_History') && size(D.Stress_History, 1) > size(D.Stress_History, 2)
                D.Sigma_History = D.Stress_History'; % Crea il campo Sigma_History trasposto
            else
                D.Sigma_History = zeros(length(D.z), length(D.x)); % Fallback
            end

            % 3. Ricostruisci gli indici dei Picchi (Sotto i rulli)
            % Il CIM non li calcola nativamente, li troviamo geometricamente ora
            if ~isfield(D, 'Idx_Peak')
                D.Idx_Peak = zeros(length(D.Machine.Xc), 1);
                for i = 1:length(D.Machine.Xc)
                    [~, D.Idx_Peak(i)] = min(abs(D.x - D.Machine.Xc(i)));
                end
            end

            % 4. Estrai Stress ai Picchi (Serve per i punti rossi nel grafico isteresi)
            if ~isfield(D, 'Stress_At_Peaks')
                D.Stress_At_Peaks = D.Sigma_History(:, D.Idx_Peak);
            end

            % 5. Campi Dummy per evitare errori su grafici non supportati dal CIM
            if ~isfield(D, 'Plastic_Profile'), D.Plastic_Profile = zeros(size(D.x)); end
            if ~isfield(D, 'Yield_Rolls'), D.Yield_Rolls = zeros(length(D.z), length(D.Machine.Xc)); end

            % Salva dati adattati
            app.CurrentDetailData = D;
            
            x_lims = [-p.P, (p.N+1)*p.P];


            % --- Grafico 1: Macchina & Linea Elastica ---
            ax = app.Ax_Machine;
            cla(ax); grid(ax, 'on'); hold(ax, 'on'); box(ax, 'on'); axis(ax, 'equal');

            % 1. Ricostruzione Linea Elastica Diretta da Kappa
            % Questo metodo funziona SEMPRE, sia per FDM che per CIM
            if isfield(D, 'Kappa') && isfield(D, 'x')
                x_plot = D.x;

                % Doppia integrazione numerica della curvatura
                % Theta(x) = int(Kappa) dx
                theta_plot = cumtrapz(x_plot, D.Kappa);
                % y(x) = int(Theta) dx
                y_plot = cumtrapz(x_plot, theta_plot);

                % (Opzionale) Ruota per allineare l'ultimo rullo se necessario
                % Ma per ora il shift verticale è sufficiente per vedere la forma.
            else
                x_plot = []; y_plot = [];
            end

            % Disegno Lamiera (Blu solido con spessore)
            thk = p.t;
            if ~isempty(x_plot)
                X_poly = [x_plot; flipud(x_plot)];
                Y_poly = [y_plot + thk/2; flipud(y_plot - thk/2)];
                fill(ax, X_poly, Y_poly, [0.4 0.7 1.0], 'EdgeColor', 'b', 'FaceAlpha', 0.8);
            end

            % 2. Disegno Rulli
            Mchn = D.Machine;
            theta = linspace(0, 2*pi, 60);

            for i = 1:length(Mchn.Xc)
                cx = Mchn.Xc(i);
                cy = Mchn.Yc(i);

                % Corpo Rullo (Grigio)
                fill(ax, cx + Mchn.R*cos(theta), cy + Mchn.R*sin(theta), ...
                    [0.85 0.85 0.85], 'EdgeColor', 'k');

                % Centro Rullo (+)
                plot(ax, cx, cy, 'k+', 'MarkerSize', 6);

                % --- NUOVO: PUNTO DI CONTATTO E ANGOLO (Dati dal Kernel) ---
                if isfield(D, 'Contact_Angles_Rad') && length(D.Contact_Angles_Rad) >= i
                    
                    angle_rad = D.Contact_Angles_Rad(i);
                    angle_deg = angle_rad * (180 / pi); % Più leggibile per l'utente

                    R_eff_plot = Mchn.R + p.t/2;
                    
                    % Calcolo coordinate reali del punto di tangenza
                    if mod(i, 2) ~= 0
                        % Rullo Dispari (Inferiore): la lamiera poggia sopra
                        x_cnt = cx - R_eff_plot * sin(angle_rad);
                        y_cnt = cy + R_eff_plot * cos(angle_rad);
                        txt_y = y_cnt - p.R * 0.6; % Testo sotto la lamiera
                        va = 'bottom';
                    else
                        % Rullo Pari (Superiore): la lamiera preme sotto
                        x_cnt = cx + R_eff_plot * sin(angle_rad);
                        y_cnt = cy - R_eff_plot * cos(angle_rad);
                        txt_y = y_cnt + p.R * 0.6; % Testo sopra la lamiera
                        va = 'top';
                    end

                    % A. Punto Rosso (Contatto sulla lamiera)
                    plot(ax, x_cnt, y_cnt, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 5);

                    % B. Testo Angolo (Gradi)
                    text(ax, cx, txt_y, sprintf('%.2f°', angle_deg), ...
                        'HorizontalAlignment', 'center', 'Color', 'r', ...
                        'FontSize', 9, 'VerticalAlignment', va, 'FontWeight', 'bold');
                end
            end

            % Limiti assi: allarga un po' per vedere entrata/uscita
            if ~isempty(x_plot)
                xlim(ax, [min(x_plot)-p.P, max(x_plot)+p.P]);
                % Auto-scale Y per vedere bene la deformazione (centrata sullo spessore)
                ylim(ax, [-p.R*2.2, p.R*2.2]); % Zoom sui rulli
            end

            ax.Title.String = 'Elastic line';
            xlabel(ax, 'Length [mm]'); ylabel(ax, 'Hight [mm]');


            % --- Grafico 2: Curvatura (Nuova Versione CIM) ---
            ax = app.Ax_Curvature;
            cla(ax); grid(ax, 'on'); hold(ax, 'on'); box(ax, 'on');

            % Recupera Curvatura Globale
            k_plot = []; x_k_plot = [];

            if isfield(D, 'Kappa') && length(D.Kappa) > length(D.Machine.Xc)
                % Se il kernel ha restituito la storia completa (array lungo)
                k_plot = D.Kappa;
                x_k_plot = D.x;
            elseif isfield(D, 'Segments')
                % --- OTTIMIZZAZIONE PREALLOCAZIONE ---
                num_seg = length(D.Segments);
                if num_seg > 0
                    % Calcoliamo i punti totali:
                    % Il primo segmento ha N punti, i successivi (N-1) perché togliamo la sovrapposizione
                    pts_per_seg = length(D.Segments(1).x_global);
                    total_pts = pts_per_seg + (num_seg - 1) * (pts_per_seg - 1);

                    % 1. Preallocazione (molto più veloce)
                    x_k_plot = zeros(total_pts, 1);
                    k_plot   = zeros(total_pts, 1);

                    % 2. Riempimento indicizzato
                    curr_idx = 1;
                    for k = 1:num_seg
                        xk = D.Segments(k).x_global;
                        kk = D.Segments(k).Curvature;

                        if k > 1
                            xk(1) = []; kk(1) = []; % Rimuovi punto sovrapposto
                        end

                        n = length(xk);
                        x_k_plot(curr_idx : curr_idx + n - 1) = xk;
                        k_plot(curr_idx : curr_idx + n - 1)   = kk;

                        curr_idx = curr_idx + n;
                    end
                else
                    x_k_plot = []; k_plot = [];
                end
            end

            if ~isempty(k_plot)
                % Disegna Area Curvatura
                area(ax, x_k_plot, k_plot * 1000, 'FaceColor', 'c', 'FaceAlpha', 0.2);
                plot(ax, x_k_plot, k_plot * 1000, 'b-', 'LineWidth', 1.5);


                % Linea Zero
                yline(ax, 0, 'k-', 'Alpha', 0.5);

                % Mostra Curvatura Residua Finale (Linea Rossa + Testo)
                if isfield(D, 'Curvature')
                    k_res = D.Curvature * 1000; % Conversione in [1/m]

                    % 1. Linea orizzontale tratteggiata
                    yline(ax, k_res, 'r--', 'LineWidth', 1.5);

                    % 2. Testo con il valore numerico
                    txt = sprintf('Res: %.3f 1/m', k_res);

                    % Posizionamento testo: Estremità destra del grafico, sopra la linea
                    x_txt = max(x_k_plot);
                    text(ax, x_txt, k_res, txt, ...
                        'VerticalAlignment', 'bottom', ...
                        'HorizontalAlignment', 'right', ...
                        'Color', 'r', 'FontSize', 9, 'FontWeight', 'bold', ...
                        'BackgroundColor', [1 1 1 0.7]); % Sfondo semitrasparente per leggibilità
                end
                % --- AGGIUNTA: Croci Rottura su Curvatura ---
                % Controlla se lo stress totale massimo ha superato Rm
                if isfield(D, 'Max_Total_Stress') && isfield(p, 'Rm') && D.Max_Total_Stress > p.Rm
                    % Trova il punto dove avviene la rottura (max curvature point o ultimo punto)
                    [~, idx_fail] = max(abs(k_plot));
                    plot(ax, x_k_plot(idx_fail), k_plot(idx_fail)*1000, 'kx', 'MarkerSize', 12, 'LineWidth', 2);
                    text(ax, x_k_plot(idx_fail), k_plot(idx_fail)*1000, ' BREAK!', 'Color', 'r', 'FontWeight', 'bold');
                end
            end

            ax.Title.String = 'Curvature Trend [1/m]';
            ylabel(ax, 'Curvatura \kappa');
            if ~isempty(x_plot), xlim(ax, [min(x_plot), max(x_plot)]); end


            % --- Grafico 3: Tasso di Plasticizzazione ---

            ax = app.Ax_Plastic;
            cla(ax); grid(ax, 'on'); hold(ax, 'on'); box(ax, 'on');

            % 1. Recupera i dati (con supporto per CIM e FDM)
            x_plast = []; y_plast = [];

            if isfield(D, 'Plastic_Profile')
                % Nuovo Kernel CIM v2.0
                x_plast = D.x;
                y_plast = D.Plastic_Profile;
            elseif isfield(D, 'Segments')
                % Fallback (se il kernel non è stato aggiornato bene)
                x_plast = D.x;
                y_plast = zeros(size(D.x));
            end

            % 2. Disegno Area Arancione
            if ~isempty(x_plast)
                area(ax, x_plast, y_plast, 'FaceColor', [1 0.5 0.2], 'FaceAlpha', 0.4, 'EdgeColor', 'none');
                plot(ax, x_plast, y_plast, 'r-', 'LineWidth', 1.5);

                % Target Line (Solitamente si punta all'80% sui primi rulli)
                yline(ax, 80, 'g--', 'LineWidth', 1.5, 'Label', 'Target 80%');

                % Limiti assi
                ax.YLim = [0, 100];
                if ~isempty(x_plot), xlim(ax, [min(x_plot), max(x_plot)]); end
            end

            ax.Title.String = '3. Tasso di Plasticizzazione (Penetrazione %)';
            ax.XLabel.String = 'Posizione [mm]';
            ax.YLabel.String = '% Sezione Snervata';
            
            app.Btn_Show3D.Enable = 'on';
            % Ora il numero sul bottone sarà identico a quello che vedi colorato nella mappa
            app.Btn_Show3D.Text = sprintf('Final Sheet view');

            % Sincronizzazione visiva: blocca la larghezza e collega lo zoom
            linkaxes([app.Ax_Machine, app.Ax_Curvature, app.Ax_Plastic], 'x');
            
            if isfield(D, 'x') && ~isempty(D.x)
                % Forza i limiti in modo uguale per tutti, dando un po' di margine ai lati
                x_min = min(D.x) - p.P;
                x_max = max(D.x) + p.P;
                app.Ax_Machine.XLim = [x_min, x_max];
            end
        end

        function show3DSurface(app)
            if isempty(app.CurrentDetailData) || isempty(app.CurrentSheetData)
                uialert(app.UIFigure, 'Seleziona prima un punto sulla mappa!', 'Dati Mancanti');
                return;
            end

            D = app.CurrentDetailData; 
            S = app.CurrentSheetData;  

            % Setup Finestra (più grande e pulita)
            fig_tag = 'Result3DWindow';
            f = findobj('Type', 'figure', 'Tag', fig_tag);
            if isempty(f)
                f = uifigure('Name', 'Final Leveled Sheet Geometry', 'Tag', fig_tag, ...
                             'Color', 'w', 'Position', [150 150 900 600]); 
            end
            figure(f); clf(f);
            
            % Layout diviso in 2 colonne: Grafico 3D (sinistra) e Tabella (destra)
            gl = uigridlayout(f, [1 2], 'ColumnWidth', {'1x', 340}, 'Padding', [10 10 10 10]);
            ax = uiaxes(gl);
            ax.Layout.Row = 1; ax.Layout.Column = 1;

            % Parametri Geometrici
            L_plot = 2000; 
            W = S.Geo.W;
            t_thick = S.Geo.t; % Spessore reale dal file sheet

            % Mesh ad alta risoluzione
            [X, Y] = meshgrid(linspace(0, L_plot, 100), linspace(-W/2, W/2, 50));

            if isfield(D, 'Curvature')
                k_res = D.Curvature; 
            else
                k_res = 0; 
            end

            % Asse neutro
            Z_mid = 0.5 * k_res * (X.^2);

            if isfield(D, 'Residual_Stress_Surface')
                sig_surf = D.Residual_Stress_Surface;
            else
                sig_surf = 0;
            end
            
            C = ones(size(Z_mid)) * sig_surf;

            % --- RENDERING SOLIDO 3D ---
            hold(ax, 'on');
            
            % Estradosso (Sopra) e Intradosso (Sotto)
            surf(ax, X, Y, Z_mid + t_thick/2, C, 'FaceColor', 'interp', 'EdgeColor', 'none');
            surf(ax, X, Y, Z_mid - t_thick/2, C, 'FaceColor', 'interp', 'EdgeColor', 'none');
            
            % Bordi Laterali e Frontali (Pareti grigio scuro per far risaltare il solido)
            edge_col = [0.3 0.3 0.3];
            surf(ax, [X(1,:); X(1,:)], [Y(1,:); Y(1,:)], [Z_mid(1,:)-t_thick/2; Z_mid(1,:)+t_thick/2], 'FaceColor', edge_col, 'EdgeColor', 'none'); % Dietro
            surf(ax, [X(end,:); X(end,:)], [Y(end,:); Y(end,:)], [Z_mid(end,:)-t_thick/2; Z_mid(end,:)+t_thick/2], 'FaceColor', edge_col, 'EdgeColor', 'none'); % Davanti
            surf(ax, [X(:,1)'; X(:,1)'], [Y(:,1)'; Y(:,1)'], [Z_mid(:,1)'-t_thick/2; Z_mid(:,1)'+t_thick/2], 'FaceColor', edge_col, 'EdgeColor', 'none'); % Lato SX
            surf(ax, [X(:,end)'; X(:,end)'], [Y(:,end)'; Y(:,end)'], [Z_mid(:,end)'-t_thick/2; Z_mid(:,end)'+t_thick/2], 'FaceColor', edge_col, 'EdgeColor', 'none'); % Lato DX

            % --- ESTETICA, LUCI E MATERIALI ---
            axis(ax, 'equal'); 
            axis(ax, 'tight');
            view(ax, [-45 30]);
            grid(ax, 'on'); box(ax, 'on');
            
            % Effetto metallico realistico
            colormap(ax, 'jet'); 
            lighting(ax, 'gouraud');
            material(ax, 'metal');
            camlight(ax, 'headlight');
            camlight(ax, 'left');
            
            % Colorbar potenziata
            cb = colorbar(ax); 
            cb.Label.String = 'Surface Residual Stress [MPa]';
            cb.Label.FontWeight = 'bold';
            cb.Label.FontSize = 11;
            
            % Sincronizzazione Colori
            if ~isempty(app.GridResults) && isfield(app.GridResults, 'S')
                min_S = min(app.GridResults.S(:));
                max_S = max(app.GridResults.S(:));
                if max_S > min_S
                    clim(ax, [min_S, max_S]);
                else
                    clim(ax, [min_S-5, max_S+5]); 
                end
            else
                limit_val = max(abs(sig_surf), 5);
                clim(ax, [-limit_val, limit_val]);
            end
            
            % Titoli e Assi
            title(ax, sprintf('FINAL LEVELED SHEET\nK_{res}: %.3f [1/m]  |  \\sigma_{res}: %.1f [MPa]', k_res * 1000, sig_surf), 'FontSize', 14);
            xlabel(ax, 'Length [mm]', 'FontWeight', 'bold'); 
            ylabel(ax, 'Width [mm]', 'FontWeight', 'bold'); 
            zlabel(ax, 'Z [mm]', 'FontWeight', 'bold');

            % Allarme Rottura Materiale Migliorato
            if isfield(D, 'Max_Total_Stress') && isfield(S.Mat, 'Rm') && D.Max_Total_Stress > S.Mat.Rm
                text(ax, L_plot/2, 0, max(Z_mid(:)) + t_thick*5, 'MATERIAL FAILURE!', ...
                    'Color', 'r', 'FontSize', 26, 'FontWeight', 'bold', ...
                    'HorizontalAlignment', 'center', 'BackgroundColor', [1 1 1 0.8], 'EdgeColor', 'r');
            end

            % --- ESTRAZIONE DATI DIRETTAMENTE DAL KERNEL ---
            % Nessun ricalcolo fisico: leggiamo solo la struttura D
            
            max_tot = 0; if isfield(D, 'Max_Total_Stress'), max_tot = D.Max_Total_Stress; end
            max_pl = 0;  if isfield(D, 'Plastic_Profile'), max_pl = max(D.Plastic_Profile); end
            
            alpha_surf = 0; ep_surf = 0;
            
            % Estrazione valori sulle fibre esterne (Pelle della lamiera)
            if isfield(D, 'Alpha_Final'), alpha_surf = max(abs(D.Alpha_Final([1, end]))); end
            if isfield(D, 'Eps_Pl_Final'), ep_surf = max(D.Eps_Pl_Final([1, end])); end
           

            % Costruzione Dati Tabella (con 3a colonna "Info")
            tableData = {
                'Curvatura Residua', sprintf('%.3f [1/m]', k_res * 1000), '';
                'Stress Res. Superficie', sprintf('%.1f MPa', sig_surf), '';
                'Max Stress Processo', sprintf('%.1f MPa', max_tot), '';
                'Max Penetr. Plastica', sprintf('%.1f %%', max_pl), '[ ? ]';
                'Backstress (\alpha) Pelle', sprintf('%.1f MPa', alpha_surf), '';
                'Def. Plastica Cumulata', sprintf('%.3f %%', ep_surf * 100), '[ ? ]';
            };
            
            % Aggiunta Margine Sicurezza
            if isfield(S.Mat, 'Rm')
                margin_Rm = S.Mat.Rm - max_tot;
                tableData(end+1,:) = {'Margine a Rottura (Rm)', sprintf('%.1f MPa', margin_Rm), ''};
            end

            % --- CREAZIONE PANNELLO E TABELLA UI ---
            pnlInfo = uipanel(gl, 'Title', 'Stato Finale (Dati Kernel)', 'FontWeight', 'bold', 'FontSize', 14);
            pnlInfo.Layout.Row = 1; pnlInfo.Layout.Column = 2;
            
            glInfo = uigridlayout(pnlInfo, [1, 1], 'Padding', [5 5 5 5]);
            
            tInfo = uitable(glInfo, 'Data', tableData, 'ColumnName', {'Parametro', 'Valore', 'Info'}, ...
                'RowName', [], 'FontName', 'Consolas', 'FontSize', 12);
            tInfo.Layout.Row = 1; tInfo.Layout.Column = 1;
            tInfo.ColumnWidth = {'fit', '1x', 45};
            
            % --- CALLBACK CLICK SULLA TABELLA ---
            tInfo.CellSelectionCallback = @(src, event) handleInfoClick(event, f, tableData);
            
            hold(ax, 'off');
            
            % =========================================================
            % FUNZIONE ANNIDATA: Gestione dei Popup Info (Info Point)
            % =========================================================
            function handleInfoClick(event, fig, data)
                if isempty(event.Indices), return; end
                r = event.Indices(1); % Riga cliccata
                c = event.Indices(2); % Colonna cliccata
                
                if c == 3 % Se l'utente clicca sulla colonna "Info" [ ? ]
                    paramName = data{r, 1};
                    
                    if contains(paramName, 'Def. Plastica Cumulata')
                        msg = sprintf(['Non misura l''allungamento netto del foglio, ma il "chilometraggio plastico" o lavoro interno.\n\n' ...
                                       'È la somma assoluta di tutte le trazioni e compressioni plastiche subite dalla fibra ' ...
                                       'piegandosi alternativamente sotto i rulli.\n\n' ...
                                       'Valori alti indicano che il materiale si è fortemente "impastato" e incrudito internamente.']);
                        uialert(fig, msg, 'Info: Def. Plastica Cumulata', 'Icon', 'info');
                    
                    elseif contains(paramName, 'Max Penetr. Plastica')
                        msg = sprintf(['Indica la percentuale massima dello spessore della lamiera che ha superato ' ...
                                       'il limite di snervamento elastico (Sy) durante il processo.\n\n' ...
                                       'Ad esempio, un valore dell''80%% indica che solo il 20%% centrale (il "nucleo" o asse neutro) ' ...
                                       'è rimasto in campo elastico, garantendo una buona efficacia di spianatura.']);
                        uialert(fig, msg, 'Info: Penetrazione Plastica', 'Icon', 'info');
                    end
                end
            end
        end


        % --- POPUP: STRESS RESIDUO + SOTTO CARICO (SENZA LEGENDA) ---
        function openStressWindow(app)
            if isempty(app.CurrentDetailData), return; end
            D = app.CurrentDetailData;
            N = length(D.Machine.Xc);

            f = uifigure('Name', 'Analisi Stress per Rullo', 'Position', [100 100 1100 600]);
            t = tiledlayout(f, 'flow', 'Padding', 'compact', 'TileSpacing', 'compact');

            % % --- INIZIO AGGIUNTA: Riquadro 0 (Ingresso/Decoiling) ---
            %
            % % 1. Calcolo Stress Iniziale (basato su R_coil dell'input)
            % % Nota: D.p contiene i parametri della lamiera (E, Sy, ecc)
            % if isfield(app.UIFigure.Children, 'Edit_CoilRad') % Controllo sicurezza
            %     R_c = app.Edit_CoilRad.Value;
            % else
            %     R_c = 800; % Fallback se non definito
            % end
            %
            % % Calcolo profilo: Sigma = E * (y / R) tappato a Sy
            % sig_in = (D.z ./ R_c) * D.p.E;
            % sig_in = max(min(sig_in, D.p.Sy), -D.p.Sy); % Taglio plastico
            %
            % % 2. Creazione Plot
            % ax0 = nexttile(t);
            % hold(ax0, 'on'); grid(ax0, 'on'); box(ax0, 'on');
            %
            % % Disegno linee limite elastico (Sfondo o riferimento)
            % xline(ax0, D.p.Sy, 'r--', 'Alpha', 0.5);
            % xline(ax0, -D.p.Sy, 'r--', 'Alpha', 0.5);
            % xline(ax0, 0, 'k-', 'Alpha', 0.3);
            %
            % % Plot Stress
            % plot(ax0, sig_in, D.z, 'r-', 'LineWidth', 2);
            %
            % % Estetica
            % ax0.Title.String = sprintf('Ingresso\n(R_{coil}=%.0f)', R_c);
            % ax0.XLabel.String = 'MPa';
            %
            % % Imposta scala asse X coerente con gli altri grafici (o fissa su Sy)
            % max_s = max(D.p.Sy * 1.2, max(abs(sig_in)));
            % xlim(ax0, [-max_s, max_s]);

            for i = 1:N
                ax = nexttile(t); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
                z_vals = D.z;

                % 1. DISEGNO ZONA ROSSA (Sfondo)
                is_plast = D.Yield_Rolls(:, i) > 0.5;
                if any(is_plast)
                    for j = 1:length(z_vals)
                        if is_plast(j)
                            dz = z_vals(2)-z_vals(1);
                            fill(ax, [-1e9 1e9 1e9 -1e9], ...
                                [z_vals(j)-dz/2, z_vals(j)-dz/2, z_vals(j)+dz/2, z_vals(j)+dz/2], ...
                                [1 0.85 0.85], 'EdgeColor', 'none');
                        end
                    end
                end

                % 2. STRESS SOTTO CARICO (Grigio Tratteggiato)
                if isfield(D, 'Stress_At_Peaks')
                    plot(ax, D.Stress_At_Peaks(:, i), D.z, ...
                        'Color', [0.4 0.4 0.4], 'LineStyle', '--', 'LineWidth', 1.5);
                end

                % 3. STRESS RESIDUO (Blu Continuo)
                plot(ax, D.Roll_Residuals(:, i), D.z, 'b.-', 'LineWidth', 1.5);

                xline(ax, 0, 'k'); % Asse zero

                ax.Title.String = sprintf('Rullo %d', i);

                % Limiti assi intelligenti
                max_res = max(abs(D.Roll_Residuals(:)));
                max_load = 0;
                if isfield(D, 'Stress_At_Peaks'), max_load = max(abs(D.Stress_At_Peaks(:))); end
                limit_x = max(max_res, max_load) * 1.1;
                if limit_x == 0, limit_x = 10; end
                ax.XLim = [-limit_x, limit_x];
            end
        end

        function openMaterialWindow(app)
            if isempty(app.CurrentDetailData), return; end
            p = app.CurrentDetailData.p;
            f = uifigure('Name','Materiale','Position',[300 300 500 400]);
            ax = uiaxes(f,'Position',[50 50 400 300]); grid(ax,'on');
            ep = linspace(0,0.05,100); sig=zeros(size(ep));
            for i=1:length(ep), v=ep(i);
                if p.ModelType==1, R=p.Sy+p.H_iso*v;
                elseif p.ModelType==2, R=p.Sy+p.K_hol*(v^p.n_hol);
                elseif p.ModelType==3, R=p.S_sat-(p.S_sat-p.Sy)*exp(-p.b_voce*v); end
                sig(i)=R;
            end
            plot(ax,ep*100,sig,'k-','LineWidth',2); xlabel(ax,'%'); ylabel(ax,'Stress');
        end

        function onMapClick(app, src, event)
            if isempty(app.GridResults), return; end
            pt = event.IntersectionPoint; app.updateDetailPlots(pt(1), pt(2), false);
        end

        function onModelChange(app, ~)
            val = app.Drop_Model.Value;
            if strcmp(val, 'Lineare'), app.Label_Spec1.Text='H_iso'; app.Edit_Spec1.Value=500; app.Label_Spec2.Visible='off'; app.Edit_Spec2.Visible='off';
            elseif strcmp(val, 'Ludwik'), app.Label_Spec1.Text='K'; app.Edit_Spec1.Value=500; app.Label_Spec2.Visible='on'; app.Label_Spec2.Text='n'; app.Edit_Spec2.Value=0.25;
            elseif strcmp(val, 'Voce'), app.Label_Spec1.Text='S_sat'; app.Edit_Spec1.Value=450; app.Label_Spec2.Visible='on'; app.Label_Spec2.Text='b'; app.Edit_Spec2.Value=8;
            end
        end

        % --- POPUP: CICLO ISTERESI INTERATTIVO CON SLIDER ---
        function openHysteresisWindow(app)
            if isempty(app.CurrentDetailData), return; end
            D = app.CurrentDetailData;
            p = D.p;

            % Check compatibilità Kernel
            if ~isfield(D, 'Sigma_History')
                uialert(app.UIFigure, 'Ricompila il Kernel per supportare la storia completa (Sigma_History)!', 'Dati Mancanti');
                return;
            end

            % Layout Finestra
            f = uifigure('Name', 'Ciclo Isteresi Interattivo', 'Position', [150 150 800 600]);
            gl = uigridlayout(f, [2, 1]);
            gl.RowHeight = {'1x', 80}; % Grafico sopra, Controlli sotto

            % Grafico
            ax = uiaxes(gl);
            grid(ax, 'on'); hold(ax, 'on'); box(ax, 'on');
            xlabel(ax, 'Strain Totale \epsilon'); ylabel(ax, 'Stress \sigma [MPa]');

            % Pannello Controlli
            pnl = uipanel(gl, 'Title', 'Posizione Fibra (Spessore z)');

            % Slider
            sld = uislider(pnl, 'Position', [50 40 600 3], ...
                'Limits', [-p.t/2, p.t/2], ...
                'Value', p.t/2, ... % Default: Top
                'ValueChangedFcn', @(src,e) updatePlot(src.Value));

            % Label Valore
            lbl = uilabel(pnl, 'Position', [680 30 100 30], 'Text', sprintf('z = %.2f', p.t/2), 'FontSize', 14, 'FontWeight', 'bold');

            % --- Funzione Aggiornamento ---
            function updatePlot(z_req)
                cla(ax); hold(ax, 'on'); grid(ax, 'on');

                % 1. Trova indice layer più vicino
                [~, idx_z] = min(abs(D.z - z_req));
                z_act = D.z(idx_z);
                lbl.Text = sprintf('z = %.2f', z_act);
                title(ax, sprintf('Ciclo Isteresi Fibra z = %.2f mm', z_act));

                % 2. Recupera Storie per questa fibra
                Sig_Hist = D.Sigma_History(idx_z, :);
                % Strain Totale = -z * (K_geo - K0)
                Eps_Hist = -z_act * (D.Kappa_Geo - p.K0);

                % Plot Linea Blu (Percorso)
                plot(ax, Eps_Hist, Sig_Hist, 'b-', 'LineWidth', 1.5);

                % 3. Loop Rulli (Punti Rossi + Springback)
                for i = 1:length(D.Machine.Xc)
                    idx_pk = D.Idx_Peak(i);

                    % A. Punto Sotto Carico (Load)
                    eps_load = Eps_Hist(idx_pk);
                    sig_load = Sig_Hist(idx_pk);

                    plot(ax, eps_load, sig_load, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 6);
                    text(ax, eps_load, sig_load, sprintf(' R%d', i), 'VerticalAlignment', 'bottom');

                    % B. Punto Residuo (Simulato)
                    % Prende lo stress residuo specifico di QUESTA fibra (riga idx_z)
                    sig_res = D.Roll_Residuals(idx_z, i);

                    % Calcolo strain residuo (scarico elastico)
                    eps_res = eps_load - (sig_load - sig_res) / p.E;

                    plot(ax, eps_res, sig_res, 'rx', 'MarkerSize', 8, 'LineWidth', 2);

                    % C. Linea Springback Tratteggiata
                    plot(ax, [eps_load, eps_res], [sig_load, sig_res], 'r:', 'LineWidth', 1.2);
                end
            end

            % Primo plot
            updatePlot(p.t/2);
        end

        function openInitialStateWindow(app)
            if isempty(app.CurrentSheetData)
                uialert(app.UIFigure, 'Please load a Sheet file (.sheet) first!', 'Data Missing');
                return;
            end

            S = app.CurrentSheetData;

            % --- WINDOW SETUP ---
            f = uifigure('Name', 'Initial Sheet State - Technical Summary', ...
                'Position', [150 150 1100 600]);

            gl = uigridlayout(f, [1, 2]);
            gl.ColumnWidth = {350, '1x'};
            gl.RowHeight = {'1x'};

            % --- LEFT SIDE: TEXTUAL SUMMARY ---
            pnlInfo = uipanel(gl, 'Title', 'Sheet Properties & Metallurgy', 'FontWeight', 'bold');
            pnlInfo.Layout.Row = 1; pnlInfo.Layout.Column = 1;

            gi = uigridlayout(pnlInfo, [18, 2]); % Aumentato il numero di righe
            gi.RowHeight = repmat({22}, 1, 18);
            gi.ColumnWidth = {'fit', '1x'};

            % Puntatore riga interno
            r_idx = 1;

            % --- Helper Function Interna (Sintassi sicura) ---
            function addRowInfo(lblStr, valStr)
                l_prop = uilabel(gi, 'Text', lblStr, 'FontWeight', 'bold');
                l_prop.Layout.Row = r_idx; l_prop.Layout.Column = 1;

                l_val = uilabel(gi, 'Text', valStr);
                l_val.Layout.Row = r_idx; l_val.Layout.Column = 2;

                r_idx = r_idx + 1;
            end

            % --- CATEGORIA: GEOMETRY ---
            l_cat1 = uilabel(gi, 'Text', '--- GEOMETRY ---', 'FontAngle', 'italic', 'FontWeight', 'bold');
            l_cat1.Layout.Row = r_idx; l_cat1.Layout.Column = [1 2]; r_idx = r_idx + 1;

            addRowInfo('Thickness:', [num2str(S.Geo.t) ' mm']);
            addRowInfo('Width:', [num2str(S.Geo.W) ' mm']);

            % --- CATEGORIA: MATERIAL ---
            l_cat2 = uilabel(gi, 'Text', '--- MATERIAL ---', 'FontAngle', 'italic', 'FontWeight', 'bold');
            l_cat2.Layout.Row = r_idx; l_cat2.Layout.Column = [1 2]; r_idx = r_idx + 1;

            addRowInfo('Young Modulus (E):', [num2str(S.Mat.E) ' MPa']);
            addRowInfo('Yield Strength (Sy):', [num2str(S.Mat.Sy) ' MPa']);
            addRowInfo('UTS (sy):', [num2str(S.Mat.Rm) 'MPa']);
            addRowInfo('Hardening Model:', char(S.Mat.Model));
            if isfield(S.Mat, 'H_kin')
                addRowInfo('Kinematic Mod. (H):', [num2str(S.Mat.H_kin) ' MPa']);
            end

            % --- CATEGORIA: INPUT DEFECTS ---
            l_cat3 = uilabel(gi, 'Text', '--- INPUT DEFECTS ---', 'FontAngle', 'italic', 'FontWeight', 'bold');
            l_cat3.Layout.Row = r_idx; l_cat3.Layout.Column = [1 2]; r_idx = r_idx + 1;

            addRowInfo('Curvature K0:', [num2str(S.Defects.K0_Geo * 1000) ' 1/m']);
            addRowInfo('Crossbow KT:', [num2str(S.Defects.K_Trans_Geo * 1000) ' 1/m']);
            addRowInfo('Residual Stress:', [num2str(S.Defects.Sig_Long) ' MPa']);
            addRowInfo('Wave Height (H):', [num2str(S.Defects.H_mm) ' mm']);
            addRowInfo('Wave Pitch (L):', [num2str(S.Defects.L_mm) ' mm']);

            if isfield(S.Defects, 'I_Units')
                addRowInfo('Flatness Error:', [num2str(S.Defects.I_Units, '%.1f') ' I-Units']);
            end

            % --- PDF REPORT BUTTON ---
            r_idx = r_idx + 1;
            btnPDF = uibutton(gi, 'Text', 'GENERATE PDF REPORT', ...
                'BackgroundColor', [0.6 0 0], 'FontColor', 'w', 'FontWeight', 'bold');
            btnPDF.Layout.Row = r_idx;
            btnPDF.Layout.Column = [1 2];

            % --- RIGHT SIDE: 3D PREVIEW ---
            ax3D = uiaxes(gl);
            ax3D.Layout.Row = 1; ax3D.Layout.Column = 2;

            % 1. Replica mesh densa di SheetSpecApp
            [X, Y] = meshgrid(linspace(0, 2000, 150), linspace(-S.Geo.W/2, S.Geo.W/2, 80));

            % 2. Parametri e WaveType (allineato a update3DPreview)
            H = S.Defects.H_mm;
            L = S.Defects.L_mm; if L == 0, L = 500; end

            % 3. Logica WaveType
            y_norm_sq = (2*Y/S.Geo.W).^2;
            waveType = 'Edge Waves';
            if isfield(S.Defects, 'WaveType'), waveType = S.Defects.WaveType; end

            if strcmpi(waveType, 'Edge Waves')
                profile = y_norm_sq;
            elseif strcmpi(waveType, 'Center Buckles')
                profile = (1 - y_norm_sq);
            else
                profile = (y_norm_sq - 0.5);
            end

            % 4. CALCOLO GEOMETRIA "ENHANCED" (Come SheetSpecApp riga 159)
            % Nota il fattore * 10 su H e il K0 diviso per 1000 se non già fatto
            % Nel generatore K0 è salvato in unità base, qui assumiamo coerenza
            %Z_geo = 0.5 * S.Defects.K0_Geo * X.^2 + 0.5 * S.Defects.K_Trans_Geo * Y.^2;

            % -- A. Curvatura Longitudinale (Coil Set) esatta --
            K0 = S.Defects.K0_Geo;
            if abs(K0) > 1e-9
                R = 1/K0;
                % Calcolo esatto arco di cerchio (evita radici immaginarie)
                Z_Coil = R - sign(R) * sqrt(max(0, R^2 - X.^2));
                
                % "Nascondi" i punti oltre il raggio (se la lamiera si chiude su se stessa)
                Z_Coil(X > abs(R)) = NaN; 
            else
                Z_Coil = 0;
            end

            % -- B. Crossbow Trasversale esatto --
            KT = S.Defects.K_Trans_Geo;
            if abs(KT) > 1e-9
                RT = 1/KT;
                % Calcolo esatto arco per la larghezza (Y)
                Z_Cross = RT - sign(RT) * sqrt(max(0, RT^2 - Y.^2));
                Z_Cross(abs(Y) > abs(RT)) = NaN;
            else
                Z_Cross = 0;
            end
            
            Z_geo = Z_Coil + Z_Cross;

            % *** IL TRUCCO VISIVO DEL GENERATORE ***
            % Moltiplica H per 10 per esasperare il difetto nel grafico
            Z_wave = ( H / 2) * profile .* sin(2*pi*X/L);

            Z_tot = Z_geo + Z_wave;

            % 5. CALCOLO COLORE "HYBRID" (Come SheetSpecApp riga 167)
            % Il colore è un mix di Stress Longitudinale, Trasversale e Forma Onda
            Sig_L_val = S.Defects.Sig_Long;

            % Ricostruzione Stress Trasversale (se salvato, altrimenti stima)
            if isfield(S.Defects, 'Sig_Trans'), Sig_T_peak = S.Defects.Sig_Trans; else, Sig_T_peak = 0; end
            Sig_T_profile = Sig_T_peak * (y_norm_sq - 0.5);

            % Formula esatta del generatore per i colori
            ColorData = Sig_L_val + Sig_T_profile + (Z_wave * 2);

            % 6. RENDERING (Come SheetSpecApp riga 169)
            % Usiamo ColorData come quarto argomento invece di Z_tot per i colori
            surf(ax3D, X, Y, Z_tot, ColorData, 'EdgeColor', 'none', 'FaceColor', 'interp');

            axis(ax3D, 'equal'); % Fondamentale per il "look" compatto
            axis(ax3D, 'tight');
            view(ax3D, [-45 30]);

            colormap(ax3D, 'jet'); % Jet per matchare lo screenshot
            camlight(ax3D, 'headlight');
            lighting(ax3D, 'gouraud');
            grid(ax3D, 'on'); box(ax3D, 'on');

            title(ax3D, ['Initial Surface Preview: ' waveType]);xlabel(ax3D, 'Length [mm]'); ylabel(ax3D, 'Width [mm]'); zlabel(ax3D, 'Z [mm]');

            % Callback PDF (Invariato)
            btnPDF.ButtonPushedFcn = @(s,e) app.generateInitialPDF(S, ax3D);
        end

        function generateInitialPDF(app, S, axSource)
            % Chiede all'utente dove salvare il file
            [file, path] = uiputfile('Initial_Sheet_Report.pdf', 'Save Technical Report');
            if isequal(file,0), return; end

            % 1. Cattura l'immagine dal grafico 3D usando exportgraphics
            % Questa è la funzione standard di MATLAB per catturare gli assi
            tempImg = [tempname '.png'];
            try
                exportgraphics(axSource, tempImg, 'Resolution', 300);
            catch
                % Fallback se l'hardware grafico non supporta exportgraphics in background
                saveas(axSource, tempImg);
            end

            % 2. Inizio creazione documento (Richiede MATLAB Report Generator)
            import mlreportgen.dom.*
            doc = Document(fullfile(path, file), 'pdf');

            % Intestazione
            p_title = Paragraph('TECHNICAL DATA SHEET: INITIAL STATE', 'Heading1');
            p_title.Color = 'DarkBlue';
            p_title.HAlign = 'center';
            append(doc, p_title);
            append(doc, HorizontalRule());

            % Sezione Material & Geometry
            append(doc, Paragraph(['Report Date: ' char(datetime('now'))], 'Normal'));
            append(doc, Paragraph('--- Material & Geometry Properties ---', 'Heading2'));

            % Preparazione Tabella Dati
            tableData = {
                'Property Description', 'Value', 'Unit';
                'Sheet Thickness', S.Geo.t, 'mm';
                'Sheet Width', S.Geo.W, 'mm';
                'Yield Strength (Sy)', S.Mat.Sy, 'MPa';
                'Young Modulus (E)', S.Mat.E, 'MPa';
                'Hardening Model', char(S.Mat.Model), '-';
                'Initial Curvature (K0)', S.Defects.K0_Geo, '1/m';
                'Initial Crossbow (KT)', S.Defects.K_Trans_Geo, '1/m';
                'Flatness Error', S.Defects.I_Units, 'I-Units'
                };

            tbl = Table(tableData);
            tbl.Border = 'single';
            tbl.ColSep = 'single';
            tbl.RowSep = 'single';
            tbl.Width = '100%';
            append(doc, tbl);

            % Inserimento Immagine 3D
            append(doc, Paragraph('--- 3D Initial Surface Preview ---', 'Heading2'));
            img = Image(tempImg);
            img.Width = '5.5in'; % Dimensione ottimizzata per foglio A4

            % Centratura immagine tramite un paragrafo
            p_img = Paragraph('');
            p_img.HAlign = 'center';
            append(p_img, img);
            append(doc, p_img);

            % Chiusura e pulizia
            close(doc);
            if exist(tempImg, 'file'), delete(tempImg); end

            % Notifica successo e apertura automatica
            uialert(app.UIFigure, 'Technical Report Generated Successfully!', 'PDF Export Complete');
            if ispc, winopen(fullfile(path, file)); end
        end

        function saveSession(app)
            if isempty(app.GridResults), return; end
            [file, path] = uiputfile('Sessione.mat');
            if isequal(file,0), return; end
            ResultsToSave = app.GridResults;
            save(fullfile(path, file), 'ResultsToSave');
        end

        function loadSheet(app)
            [file, path] = uigetfile('*.sheet', 'Seleziona File Lamiera');
            if isequal(file,0), return; end

            try
                data = load(fullfile(path, file), '-mat');
                S = data.Sheet;
                app.CurrentSheetData = S;

                % Aggiorna Label Informativa
                %i_units = 0;
                %if isfield(S.Defects, 'I_Units'), i_units = S.Defects.I_Units; end

                infoStr = sprintf("Sheet Loaded \nThickness: %.1f mm | Width: %.0f mm\nSy: %.0f MPa | E: %.0f MPa\nDefect: K0=%.2f 1/mm", ...
                    S.Geo.t, S.Geo.W, S.Mat.Sy, S.Mat.E, S.Defects.K0_Geo * 1000);


                app.Lbl_SheetInfo.Text = infoStr;
                app.Lbl_SheetInfo.FontColor = [0 0.4 0]; % Verde scuro

                % Abilita Anteprima
                app.Btn_ShowInitial.Enable = 'on';
                app.Btn_ShowInitial.Visible = 'on';
                app.Btn_Run.Enable = 'on';

            catch
                uialert(app.UIFigure, 'File non valido o corrotto.', 'Errore');
            end
        end

        function loadSession(app)
            [file, path] = uigetfile('*.mat', 'Apri Sessione');
            if isequal(file,0), return; end
            data = load(fullfile(path, file));
            app.GridResults = data.ResultsToSave;
            % Ripristina solo input Macchina
            b = app.GridResults.Base;
            app.Edit_N.Value = b.N; app.Edit_P.Value = b.P; app.Edit_R.Value = b.R;
            app.Edit_I_in.Value = b.I_in; app.Edit_I_out.Value = b.I_out;
            app.Edit_Fc.Value = b.Fc; app.Edit_Fl.Value = b.Fl;

            % Ricostruisce CurrentSheetData dai dati salvati se necessario
            % (Per semplicità, qui ricarichiamo i grafici)
            [~, idx] = min(app.GridResults.S(:));
            app.updateDetailPlots(app.GridResults.X(idx), app.GridResults.Y(idx));
        end

        function onSliderChange(app, src, ~)
            % Callback quando l'utente muove lo slider
            idx = round(src.Value);
            app.updateStripPlots(idx);
        end

        function [S_new, msg_summary] = calculateResidualFlatness(app)
            % Recupera Dati
            D = app.CurrentDetailData;
            p = D.p; 
            S = app.CurrentSheetData;

            % --- RICALCOLO RIGOROSO PLANARITÀ (Metodo Fibre) ---
            n_strips = 9; 
            y_vals = linspace(-S.Geo.W/2, S.Geo.W/2, n_strips);
            mach_strain = zeros(1, n_strips);

            dl = uiprogressdlg(app.UIFigure, 'Title', 'Calcolo', 'Message', 'Analisi Planarità Residua...');
            
            try
                % A. Calcolo Strain Macchina
                for i = 1:n_strips
                    p_sim = p; 
                    p_sim.y_coord = y_vals(i);
                    
                    % Ricostruzione Difetto Input per il Kernel
                    if S.Defects.L_mm > 0
                        wav_amp_k = (S.Defects.H_mm / S.Defects.L_mm)^2 * 246760 * 1e-5;
                    else
                        wav_amp_k = 0;
                    end
                    
                    y_norm = (2 * y_vals(i) / S.Geo.W).^2;
                    if strcmpi(S.Defects.WaveType, 'Center Buckles')
                        prof = 1 - y_norm;
                    elseif strcmpi(S.Defects.WaveType, 'Balanced')
                         prof = abs(y_norm - 0.5);
                    else % Edge Waves
                        prof = y_norm;
                    end
                    
                    p_sim.K0 = S.Defects.K0_Geo + wav_amp_k * prof;
                    
                    [~, d_sim] = Leveler_Kernel_CIM(p_sim);
                    
                    if isfield(d_sim, 'Avg_Elongation_Pct')
                        mach_strain(i) = d_sim.Avg_Elongation_Pct;
                    else
                        mach_strain(i) = 0;
                    end
                end
                
                % B. Strain Ingresso (Geometrico)
                if S.Defects.L_mm > 0
                    eps_max_in = (pi^2 * S.Defects.H_mm^2) / (4 * S.Defects.L_mm^2) * 100; 
                else
                    eps_max_in = 0;
                end
                
                y_all_norm = (2 * y_vals / S.Geo.W).^2;
                if strcmpi(S.Defects.WaveType, 'Center Buckles')
                    prof_vec = 1 - y_all_norm;
                elseif strcmpi(S.Defects.WaveType, 'Balanced')
                    prof_vec = abs(y_all_norm - 0.5);
                else
                    prof_vec = y_all_norm;
                end
                
                strain_in = eps_max_in * prof_vec;
                
                % C. Bilancio Totale
                total_strain = strain_in + mach_strain;
                delta_eps = max(total_strain) - min(total_strain);
                
                new_I_Units = (delta_eps / 100) * 1e5;
                
                L_ref = S.Defects.L_mm; 
                if L_ref <= 0, L_ref = 500; end
                new_H_mm = (2 * L_ref / pi) * sqrt(delta_eps / 100);
                
                % D. Costruzione Struttura Output
                S_new = S;
                S_new.Defects.I_Units = new_I_Units;
                S_new.Defects.H_mm = new_H_mm;
                % Gestione robusta Curvatura (se manca, usa fallback)
                if isfield(D, 'Curvature')
                    k_res = D.Curvature;
                elseif isfield(D, 'Kappa')
                    k_res = D.Kappa(end); % Fallback approssimato
                else
                    k_res = 0;
                end

                S_new.Defects.K0_Geo = k_res;

                % Calcolo Stress Residuo Longitudinale (con segno curvatura)
                if isfield(D, 'Sigma_Res')
                    sig_val = max(abs(D.Sigma_Res([1, end])));
                    S_new.Defects.Sig_Long = sig_val * sign(k_res);
                end
                
                if isfield(D, 'Alpha_Final')
                    S_new.State.Alpha_Final = D.Alpha_Final;
                end
                
                msg_summary = sprintf('I-Units: %.1f (In: %.1f)\nH_new: %.2f mm\nK0_new: %.4f', ...
                    new_I_Units, S.Defects.I_Units, new_H_mm, S_new.Defects.K0_Geo);
                
                close(dl);
                
            catch ME
                close(dl);
                rethrow(ME);
            end
        end

        function exportResultAsSheet(app)
            if isempty(app.SimulationResults) || ~isfield(app.SimulationResults, 'Final')
                uialert(app.UIFigure, 'Apri prima il Risultato 3D per calcolare i dati finali!', 'Info'); return; 
            end
            
            Res = app.SimulationResults.Final;
            S_new = app.CurrentSheetData;
            
            % Sovrascrivi i difetti con quelli calcolati
            S_new.Defects.I_Units = Res.Scalar.Flatness;
            S_new.Defects.H_mm    = Res.H_mm_Res;  % Max H residuo
            S_new.Defects.K0_Geo  = Res.Scalar.Curv;
            S_new.Defects.K_Trans_Geo = Res.Scalar.Crossbow;
            S_new.State.Alpha_Final = app.CurrentDetailData.Alpha_Final;
            S_new.State.Eps_Pl_Final = app.CurrentDetailData.Eps_Pl_Final;
            S_new.State.Sigma_Res = app.CurrentDetailData.Sigma_Res;

            [file, path] = uiputfile('Processed.sheet');
            if isequal(file,0), return; end
            Sheet = S_new;
            save(fullfile(path, file), 'Sheet');
            uialert(app.UIFigure, 'Export completato con successo!', 'Saved');
        end

        function updateStripPlots(app, idx)
            if isempty(app.StripResultsData), return; end

            % Recupera i dati della striscia selezionata
            D = app.StripResultsData{idx};
            y_val = app.StripYCoords(idx);
            p = D.p;

            % Aggiorna Label
            app.Lbl_SliderVal.Text = sprintf('Posizione: y = %.0f mm (Striscia %d)', y_val, idx);

            % Salva come "CurrentDetailData" così i popup (Isteresi/Stress) funzionano su questa striscia
            app.CurrentDetailData = D;

            % --- 1. LINEA ELASTICA (Ax_Machine) ---
            ax = app.Ax_Machine; cla(ax); hold(ax,'on'); grid(ax,'on'); axis(ax,'equal');
            % Ricostruzione geometria
            if isfield(D, 'Kappa') && isfield(D, 'x')
                theta = cumtrapz(D.x, D.Kappa);
                y_plot = cumtrapz(D.x, theta);
                % Shift per visualizzazione (ancorato al rullo 1)
                R_eff_plot = D.Machine.R + p.t/2;
                y_start = D.Machine.Yc(1) + R_eff_plot;
                y_plot = y_plot - y_plot(1) + y_start;

                % Disegna Lamiera
                X_poly = [D.x; flipud(D.x)];
                Y_poly = [y_plot + p.t/2; flipud(y_plot - p.t/2)];
                fill(ax, X_poly, Y_poly, [0.4 0.7 1.0], 'EdgeColor', 'b', 'FaceAlpha', 0.8);
            end
            % Disegna Rulli (Semplificato per velocità)
            plot(ax, D.Machine.Xc, D.Machine.Yc, 'ko', 'MarkerSize', 10, 'LineWidth', 2);
            ax.Title.String = sprintf('1. Linea Elastica (y=%.0f)', y_val);

            % --- 2. ANDAMENTO CURVATURA (Ax_Curvature) ---
            ax = app.Ax_Curvature; cla(ax); hold(ax,'on'); grid(ax,'on');
            plot(ax, D.x, D.Kappa*1000, 'b-', 'LineWidth', 1.5);
            yline(ax, 0, 'k-');

            % Mostra Curvatura Residua Finale (Output #5 richiesto)
            if isfield(D, 'Curvature')
                k_res = D.Curvature * 1000;
                yline(ax, k_res, 'r--', 'LineWidth', 2);
                txt = sprintf('Res: %.3f 1/m', k_res);
                text(ax, max(D.x), k_res, txt, 'VerticalAlignment','bottom','HorizontalAlignment','right','Color','r');
            end
            ax.Title.String = '2. Curvatura (blu) e Residua (rosso)';

            % --- 3. TASSO DI PLASTICIZZAZIONE (Ax_Plastic) ---
            ax = app.Ax_Plastic; cla(ax); hold(ax,'on'); grid(ax,'on');
            if isfield(D, 'Plastic_Profile')
                area(ax, D.x, D.Plastic_Profile, 'FaceColor', [1 0.5 0.2], 'FaceAlpha', 0.5);
            end
            yline(ax, 80, 'g--', 'Label', 'Target 80%');
            ylim(ax, [0 100]);

            % --- 4. STRESS RESIDUO PROFILE (Ax_ResStressProfile) ---
            % Questo è il grafico dello stress residuo finale attraverso lo spessore
            ax = app.Ax_ResStressProfile; cla(ax); hold(ax,'on'); grid(ax,'on');

            if isfield(D, 'Sigma_Res')
                plot(ax, D.Sigma_Res, D.z, 'b-o', 'MarkerSize', 3, 'LineWidth', 1.5);
                xline(ax, 0, 'k-');
                xlabel(ax, 'Stress [MPa]'); ylabel(ax, 'Spessore z [mm]');

                % Max Stress Residuo Superficiale
                max_res = max(abs(D.Sigma_Res([1, end])));
                title(ax, sprintf('4. Stress Residuo (Max: %.0f MPa)', max_res));

                if isfield(D, 'Sigma_History') && isfield(p, 'Rm')
                    % Trova il massimo stress raggiunto da ogni fibra in tutta la storia
                    max_stress_per_fiber = max(abs(D.Sigma_History), [], 2);
                    idx_broken_fibers = find(max_stress_per_fiber > p.Rm);

                    if ~isempty(idx_broken_fibers)
                        % Plotta una X rossa sullo stress residuo delle fibre rotte
                        plot(ax, D.Sigma_Res(idx_broken_fibers), D.z(idx_broken_fibers), ...
                            'rx', 'MarkerSize', 8, 'LineWidth', 1.5);

                        % Aggiunge etichetta warning nel titolo
                        ax.Title.String = [ax.Title.String ' [BROKEN FIBERS]'];
                        ax.Title.Color = 'r';
                    end
                end
            end

        end
    end

    methods (Access = public)
        function app = LevelerApp
            % 1. Setup Finestra Principale
            app.UIFigure = uifigure('Name', 'Leveler Pro v2.0 - Console', 'Position', [50 50 1400 800]);
            app.GridLayoutMain = uigridlayout(app.UIFigure, [1, 2]);
            app.GridLayoutMain.ColumnWidth = {280, '1x'};

            % 2. Sidebar (Pannello Sinistro)
            app.LeftSidebar = uipanel(app.GridLayoutMain, 'Title', 'Console Comandi');

            % --- DEFINIZIONE GRIGLIA SIDEBAR ---
            sl = uigridlayout(app.LeftSidebar, [22, 4]); % Aumentato a 22 righe per sicurezza
            sl.ColumnWidth = {'1x', '1x', '0.5x', '0.5x'}; % Colonne 3 e 4 più strette per i numeri min/max
            % Imposta altezza 'fit' per adattarsi al contenuto, o fissa pixel per righe critiche
            sl.RowHeight = repmat({'fit'}, 1, 22);
            sl.Padding = [10 10 10 10];
            sl.RowSpacing = 5;

            % Mappatura Parametri per Analisi Sensibilità (X/Y Assi)
            % Colonna 1: Etichetta Dropdown | Colonna 2: Nome Variabile Struct
           % Mappatura Parametri per Analisi Sensibilità (X/Y Assi)
            % Colonna 1: Etichetta Dropdown | Colonna 2: Nome Variabile Struct
            app.VarMap = { ...
                'Intermesh IN [mm]',        'I_in'; ...
                'Intermesh OUT [mm]',       'I_out'; ...
                'Flex Center (Fc) [mm]',    'Fc'; ...
                'Flex Lateral (Fl) [mm]',   'Fl'; ...
                'Spessore (t) [mm]',        't'; ...
                'Snervamento (Sy) [MPa]',   'Sy'; ...
                'Modulo Young (E) [MPa]',   'E'; ...
                'Curvatura Init (K0) [1/m]','K0'; ...
                'Passo (P) [mm]',           'P'; ...
                'Raggio (R) [mm]',          'R'; ...
                'N. Rulli',                 'N'; ...
                % --- PARAMETRI MATERIALE AGGIUNTI ---
                'Hardening Kin. (H) [MPa]',    'H_kin'; ...
                'Linear Hard. (H_iso) [MPa]',  'H_iso'; ...   % Per Modello Lineare
                'Ludwik Strength (K) [MPa]',   'K_hol'; ...   % Per Modello Ludwik
                'Ludwik Exponent (n)',         'n_hol'; ...   % Per Modello Ludwik
                'Voce Saturation (S) [MPa]',   'S_sat'; ...   % Per Modello Voce
                'Voce Rate (b)',               'b_voce' ...   % Per Modello Voce
                };

            % --- SEZIONE 1: MACCHINA ---
            l1 = uilabel(sl, 'Text', 'MACCHINA', 'FontWeight', 'bold');
            l1.Layout.Row = 1; l1.Layout.Column = [1 4];

            l2 = uilabel(sl, 'Text', 'N Rulli:', 'HorizontalAlignment', 'right');
            l2.Layout.Row = 2; l2.Layout.Column = 1;
            app.Edit_N = uieditfield(sl, 'numeric', 'Value', 11);
            app.Edit_N.Layout.Row = 2; app.Edit_N.Layout.Column = 2;

            l3 = uilabel(sl, 'Text', 'Passo P:', 'HorizontalAlignment', 'right');
            l3.Layout.Row = 3; l3.Layout.Column = 1;
            app.Edit_P = uieditfield(sl, 'numeric', 'Value', 90);
            app.Edit_P.Layout.Row = 3; app.Edit_P.Layout.Column = 2;

            l4 = uilabel(sl, 'Text', 'Raggio R:', 'HorizontalAlignment', 'right');
            l4.Layout.Row = 4; l4.Layout.Column = 1;
            app.Edit_R = uieditfield(sl, 'numeric', 'Value', 80);
            app.Edit_R.Layout.Row = 4; app.Edit_R.Layout.Column = 2;

            % --- SEZIONE 2: PROCESSO ---
            l5 = uilabel(sl, 'Text', 'PROCESSO', 'FontWeight', 'bold');
            l5.Layout.Row = 6; l5.Layout.Column = [1 2];

            l6 = uilabel(sl, 'Text', 'I_in [mm]:', 'HorizontalAlignment', 'right');
            l6.Layout.Row = 7; l6.Layout.Column = 1;
            app.Edit_I_in = uieditfield(sl, 'numeric', 'Value', 4);
            app.Edit_I_in.Layout.Row = 7; app.Edit_I_in.Layout.Column = 2;

            l7 = uilabel(sl, 'Text', 'I_out [mm]:', 'HorizontalAlignment', 'right');
            l7.Layout.Row = 8; l7.Layout.Column = 1;
            app.Edit_I_out = uieditfield(sl, 'numeric', 'Value', 0.5);
            app.Edit_I_out.Layout.Row = 8; app.Edit_I_out.Layout.Column = 2;

            l8 = uilabel(sl, 'Text', 'Flex Cen:', 'HorizontalAlignment', 'right');
            l8.Layout.Row = 9; l8.Layout.Column = 1;
            app.Edit_Fc = uieditfield(sl, 'numeric', 'Value', 0);
            app.Edit_Fc.Layout.Row = 9; app.Edit_Fc.Layout.Column = 2;

            l9 = uilabel(sl, 'Text', 'Flex Lat:', 'HorizontalAlignment', 'right');
            l9.Layout.Row = 10; l9.Layout.Column = 1;
            app.Edit_Fl = uieditfield(sl, 'numeric', 'Value', 0);
            app.Edit_Fl.Layout.Row = 10; app.Edit_Fl.Layout.Column = 2;

            l_cr = uilabel(sl, 'Text', 'Raggio Coil [mm]:', 'HorizontalAlignment', 'right');
            l_cr.Layout.Row = 11; l_cr.Layout.Column = 1;
            app.Edit_CoilRad = uieditfield(sl, 'numeric', 'Value', 800); % Default 800mm
            app.Edit_CoilRad.Layout.Row = 11; app.Edit_CoilRad.Layout.Column = 2;

            % --- SEZIONE 3: LAMIERA (CARICAMENTO) ---
            l10 = uilabel(sl, 'Text', 'INPUT Sheet', 'FontWeight', 'bold');
            l10.Layout.Row = 12; l10.Layout.Column = [1 2];

            % Tasto Giallo per caricare
            app.Btn_LoadSheet = uibutton(sl, 'Text', 'Load Sheet', ...
                'BackgroundColor', [1 0.8 0.4], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(s,e) app.loadSheet());
            app.Btn_LoadSheet.Layout.Row = 13;
            app.Btn_LoadSheet.Layout.Column = [1 2];

            % Label Export Lamiera
            app.Btn_ExportRes = uibutton(sl, 'Text', 'Exp Sheet', ...
                'BackgroundColor', [0.8 0.4 0], 'FontColor', 'w', 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(s,e) app.exportResultAsSheet());
            app.Btn_ExportRes.Layout.Row = 13;
            app.Btn_ExportRes.Layout.Column = [3 4];

            % Label Informativa (Verde)
            app.Lbl_SheetInfo = uilabel(sl, 'Text', 'No sheet loaded.', ...
                'FontSize', 10, 'FontColor', [0.5 0.5 0.5], 'VerticalAlignment', 'top', 'WordWrap', 'on');
            app.Lbl_SheetInfo.Layout.Row = 14;
            app.Lbl_SheetInfo.Layout.Column = [1 3];

            app.Btn_ShowInitial = uibutton(sl, 'Text', 'Anteprima Input', 'Visible', 'off', 'Enable', 'off', ...
                'ButtonPushedFcn', @(s,e) app.openInitialStateWindow());
            app.Btn_ShowInitial.Layout.Row = 14;
            app.Btn_ShowInitial.Layout.Column = [3 4];

            % --- SEZIONE 4: ANALISI E CALCOLO ---
            app.Drop_AxisX = uidropdown(sl, 'Items', app.VarMap(:,1), 'Value', 'Intermesh IN [mm]');
            app.Drop_AxisX.Layout.Row = 16; app.Drop_AxisX.Layout.Column = [1 2];

            app.Edit_MinX = uieditfield(sl, 'numeric', 'Value', 1, 'Visible', 'on');
            app.Edit_MinX.Layout.Row = 16; app.Edit_MinX.Layout.Column = 3;
            app.Edit_MaxX = uieditfield(sl, 'numeric', 'Value', 6, 'Visible', 'on');
            app.Edit_MaxX.Layout.Row = 16; app.Edit_MaxX.Layout.Column = 4;



            app.Drop_AxisY = uidropdown(sl, 'Items', app.VarMap(:,1), 'Value', 'Intermesh OUT [mm]');
            app.Drop_AxisY.Layout.Row = 17; app.Drop_AxisY.Layout.Column = [1 2];

            app.Edit_MinY = uieditfield(sl, 'numeric', 'Value', 0, 'Visible', 'on');
            app.Edit_MinY.Layout.Row = 17; app.Edit_MinY.Layout.Column = 3;
            app.Edit_MaxY = uieditfield(sl, 'numeric', 'Value', 2, 'Visible', 'on');
            app.Edit_MaxY.Layout.Row = 17; app.Edit_MaxY.Layout.Column = 4;

            app.Drop_OptMode = uidropdown(sl, 'Items', {'RES STRESS', 'Curvature', 'Flatness (I-Units)', 'Crossbow'});
            app.Drop_OptMode.Layout.Row = 18; app.Drop_OptMode.Layout.Column = [1 2];

            % Tasto Verde AVVIA
            app.Btn_Run = uibutton(sl, 'Text', 'RUN', ...
                'BackgroundColor', [0 0.6 0], 'FontColor', 'w', 'FontWeight', 'bold', ...
                'Enable', 'off', ...
                'ButtonPushedFcn', @(s,e) app.prepareAnalysis());
            app.Btn_Run.Layout.Row = 18;
            app.Btn_Run.Layout.Column = [3 4];

            % --- 5. VISUALIZZAZIONI AVANZATE ---
            l_det = uilabel(sl, 'Text', 'DETTAGLI', 'FontWeight', 'bold');
            l_det.Layout.Row = 19; % Regola il numero di riga in base alla tua griglia
            l_det.Layout.Column = [1 2];

            % Riga 20: Stress Rulli & Isteresi
            app.Btn_ShowStress = uibutton(sl, 'Text', 'Roll Stress', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.openStressWindow());
            app.Btn_ShowStress.Layout.Row = 20; app.Btn_ShowStress.Layout.Column = [1 2];

            app.Btn_ShowHysteresis = uibutton(sl, 'Text', 'Hardening Cycle', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.openHysteresisWindow());
            app.Btn_ShowHysteresis.Layout.Row = 21; app.Btn_ShowHysteresis.Layout.Column = [1 2];

            app.Btn_Show3D = uibutton(sl, 'Text', 'Risultato 3D', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.show3DSurface());
            app.Btn_Show3D.Layout.Row = 22; app.Btn_Show3D.Layout.Column = [1 2];

            % % Riga 21: Materiale & 3D
            % app.Btn_ShowMat = uibutton(sl, 'Text', 'Materiale', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.openMaterialWindow());
            % app.Btn_ShowMat.Layout.Row = 21; app.Btn_ShowMat.Layout.Column = [1 2];
            %
            % app.Btn_Show3D = uibutton(sl, 'Text', 'Vista 3D', 'Enable', 'off', 'ButtonPushedFcn', @(s,e) app.show3DSurface());
            % app.Btn_Show3D.Layout.Row = 21; app.Btn_Show3D.Layout.Column = [3 4];


            % --- 3. Area Grafici (Layout Avanzato) ---
            % Griglia principale Dashboard: 2 Righe (Sinistra) x 2 Colonne
            app.DashboardGrid = uigridlayout(app.GridLayoutMain, [1, 2]);
            app.DashboardGrid.ColumnWidth = {'1.2x', '1x'};

            % Sottogriglia Sinistra (3 Grafici a cascata)
            LeftPanel = uipanel(app.DashboardGrid, 'BorderType', 'none');
            LeftPanel.Layout.Row = 1;
            LeftPanel.Layout.Column = 1;
            
            LeftLayout = tiledlayout(LeftPanel, 3, 1, 'TileSpacing', 'compact', 'Padding', 'tight');

            % 1. Macchina
            app.Ax_Machine = uiaxes(LeftLayout);
            app.Ax_Machine.Layout.Tile = 1;
            app.Ax_Machine.Title.String = 'Linea Elastica';

            % 2. Curvatura
            app.Ax_Curvature = uiaxes(LeftLayout);
            app.Ax_Curvature.Layout.Tile = 2;
            app.Ax_Curvature.Title.String = 'Curvatura Longitudinale';

            % 3. Plasticità
            app.Ax_Plastic = uiaxes(LeftLayout);
            app.Ax_Plastic.Layout.Tile = 3;
            app.Ax_Plastic.Title.String = 'Tasso Plasticizzazione';

            % LeftGrid = uigridlayout(app.DashboardGrid, [3, 1]);
            % LeftGrid.RowHeight = {'1.2x', '1x', '1x'};
            % LeftGrid.Padding = [0 0 0 0];
            % 
            % % 1. Macchina
            % app.Ax_Machine = uiaxes(LeftGrid);
            % app.Ax_Machine.Title.String = 'Linea Elastica';
            % 
            % % 2. Curvatura
            % app.Ax_Curvature = uiaxes(LeftGrid);
            % app.Ax_Curvature.Title.String = 'Curvatura Longitudinale';
            % 
            % % 3. Plasticità
            % app.Ax_Plastic = uiaxes(LeftGrid);
            % app.Ax_Plastic.Title.String = 'Tasso Plasticizzazione';

            % --- COLONNA DESTRA (Mappe + Slider) ---
            RightPanel = uigridlayout(app.DashboardGrid, [2, 2]);
            RightPanel.RowHeight = {'1x'}; %RightPanel.RowHeight = {'1x', '1x'}; % Mappa S, Mappa C, Label, Slider
            RightPanel.Padding = [0 0 0 0];
            RightPanel.ColumnWidth = {'1x'}; %RightPanel.ColumnWidth = {'1x', '1x'};
            RightPanel.RowSpacing = 5;

            app.Ax_StressMap = uiaxes(RightPanel);
            app.Ax_StressMap.Layout.Row = 2;
            app.Ax_StressMap.Layout.Column = 1;
            app.Ax_StressMap.ButtonDownFcn = @(s,e) app.onMapClick(s,e);

            app.Ax_CurvMap = uiaxes(RightPanel);
            app.Ax_CurvMap.Layout.Row = 1;
            app.Ax_CurvMap.Layout.Column = 1;
            app.Ax_CurvMap.ButtonDownFcn = @(s,e) app.onMapClick(s,e);

            % app.Ax_FlatnessMap = uiaxes(RightPanel);
            % app.Ax_FlatnessMap.Layout.Row = 2;
            % app.Ax_FlatnessMap.Layout.Column = 2;
            % app.Ax_FlatnessMap.ButtonDownFcn = @(s,e) app.onMapClick(s,e);
            % 
            % app.Ax_CrossbowMap = uiaxes(RightPanel);
            % app.Ax_CrossbowMap.Layout.Row = 1;
            % app.Ax_CrossbowMap.Layout.Column = 2;
            % app.Ax_CrossbowMap.ButtonDownFcn = @(s,e) app.onMapClick(s,e);


            % Inizializzazione Dati Vuoti
            app.CurrentSheetData = [];

            % 4. Tasti Flottanti (Posizionati in alto a destra)

            % app.Btn_Show3D = uibutton(app.UIFigure, 'Text', 'Risultato 3D', ...
            %     'Position', [430 760 120 30], 'Enable', 'off', ...
            %     'ButtonPushedFcn', @(s,e) app.show3DSurface());

            % % Tasti Sessione
            % app.Btn_Load = uibutton(app.UIFigure, 'Text', 'Apri Sessione', ...
            %     'Position', [1130 760 120 30], ...
            %     'ButtonPushedFcn', @(s,e) app.loadSession());
            %
            % app.Btn_Save = uibutton(app.UIFigure, 'Text', 'Salva Sessione', ...
            %     'Position', [1260 760 120 30], 'Enable', 'off', ...
            %     'ButtonPushedFcn', @(s,e) app.saveSession());
            % In LevelerApp.m -> Sezione Tasti Sessione/Export

            % Sotto i tasti di sessione esistenti...

        end
    end
end