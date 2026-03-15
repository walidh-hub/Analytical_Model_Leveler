classdef SheetSpecApp < matlab.apps.AppBase

    % --- PROPERTIES ---
    properties (Access = public)
        % --- WINDOWS ---
        ControlFigure      matlab.ui.Figure % Finestra Comandi (Input)
        GraphFigure        matlab.ui.Figure % Finestra Grafici (Output)
        
        % --- LAYOUT MANAGERS ---
        GridControls       matlab.ui.container.GridLayout
        GridGraphs         matlab.ui.container.GridLayout
        
        % --- LEFT COLUMN: MATERIAL ---
        Pnl_Mat       matlab.ui.container.Panel
        Ax_Mat        matlab.ui.control.UIAxes
        Edit_E, Edit_Sy,Edit_Rm, Edit_t, Edit_W
        Drop_Model
        Lbl_Par1, Edit_Par1
        Lbl_Par2, Edit_Par2
        Lbl_Hkin, Edit_Hkin
        
        % --- CENTER COLUMN: LONGITUDINAL ---
        Pnl_Long      matlab.ui.container.Panel
        
        % Param 1: Geometric K0
        Edit_K0_Min, Sld_K0, Edit_K0_Max, Edit_K0_Val
        
        % Param 2: Residual Stress
        Edit_SigL_Min, Sld_SigL, Edit_SigL_Max, Edit_SigL_Val
        
        % --- RIGHT COLUMN: TRANSVERSE & WAVES ---
        Pnl_Trans     matlab.ui.container.Panel
        
        % Param 3: Crossbow K
        Edit_KT_Min, Sld_KT, Edit_KT_Max, Edit_KT_Val
        
        % Param 4: Crossbow Stress
        Edit_SigT_Min, Sld_SigT, Edit_SigT_Max, Edit_SigT_Val
        
        % Param 5: Wave Height (H) [mm]
        Edit_H_Min, Sld_H, Edit_H_Max, Edit_H_Val
        
        % Param 6: Wave Pitch (L) [mm]
        Edit_L_Min, Sld_L, Edit_L_Max, Edit_L_Val

        % --- BOTTOM: PREVIEW & SAVE ---
        Ax_3D         matlab.ui.control.UIAxes
        Btn_Save      matlab.ui.control.Button
        
        % Trova le proprietà Axes e aggiungi queste:
        Ax_SigL, Ax_SigT

        Drop_WaveType

    end

    % --- PRIVATE METHODS (LOGIC) ---
    methods (Access = private)
        
        % 1. Helper to Create "Smart Sliders"
        function createSmartSlider(app, parentGrid, row, labelText, minV, maxV, defV, tag)
            subGrid = uigridlayout(parentGrid);
            subGrid.Layout.Row = row; 
            subGrid.Layout.Column = 1;
            subGrid.ColumnWidth = {40, '1x', 40, 50}; 
            subGrid.RowHeight = {20, 40};
            subGrid.Padding = [0 5 0 5];
            
            lbl = uilabel(subGrid, 'Text', labelText, 'FontWeight', 'bold');
            lbl.Layout.Row = 1; lbl.Layout.Column = [1 4];
            
            eMin = uieditfield(subGrid, 'numeric', 'Value', minV, 'Tag', [tag '_Min']);
            eMin.Layout.Row = 2; eMin.Layout.Column = 1;
            eMin.ValueChangedFcn = @(s,e) app.onLimitChange(s, tag);
            
            sld = uislider(subGrid, 'Limits', [minV maxV], 'Value', defV, 'Tag', [tag '_Sld']);
            sld.Layout.Row = 2; sld.Layout.Column = 2;
            sld.MajorTicks = linspace(minV, maxV, 5);
            sld.ValueChangedFcn = @(s,e) app.onSliderChange(s, tag);
            sld.ValueChangingFcn = @(s,e) app.onSliderChanging(s, tag);
            
            eMax = uieditfield(subGrid, 'numeric', 'Value', maxV, 'Tag', [tag '_Max']);
            eMax.Layout.Row = 2; eMax.Layout.Column = 3;
            eMax.ValueChangedFcn = @(s,e) app.onLimitChange(s, tag);
            
            eVal = uieditfield(subGrid, 'numeric', 'Value', defV, 'Tag', [tag '_Val']);
            eVal.Layout.Row = 2; eVal.Layout.Column = 4;
            eVal.ValueChangedFcn = @(s,e) app.onValueBoxChange(s, tag);
            
            switch tag
                case 'K0'
                    app.Edit_K0_Min = eMin; app.Sld_K0 = sld; app.Edit_K0_Max = eMax; app.Edit_K0_Val = eVal;
                case 'SigL'
                    app.Edit_SigL_Min = eMin; app.Sld_SigL = sld; app.Edit_SigL_Max = eMax; app.Edit_SigL_Val = eVal;
                case 'KT'
                    app.Edit_KT_Min = eMin; app.Sld_KT = sld; app.Edit_KT_Max = eMax; app.Edit_KT_Val = eVal;
                case 'SigT'
                    app.Edit_SigT_Min = eMin; app.Sld_SigT = sld; app.Edit_SigT_Max = eMax; app.Edit_SigT_Val = eVal;
                case 'H'
                    app.Edit_H_Min = eMin; app.Sld_H = sld; app.Edit_H_Max = eMax; app.Edit_H_Val = eVal;
                case 'L'
                    app.Edit_L_Min = eMin; app.Sld_L = sld; app.Edit_L_Max = eMax; app.Edit_L_Val = eVal;
            end
        end

        % 2. Callback: Slider Moved
        function onSliderChange(app, src, tag)
            val = src.Value;
            app.syncValueBox(tag, val);
            app.updatePlots();
        end

        function onSliderChanging(app, src, tag)
             val = src.Value;
             app.syncValueBox(tag, val);
        end

        % 3. Callback: Value Box Changed
        function onValueBoxChange(app, src, tag)
            val = src.Value;
            switch tag
                case 'K0', app.Sld_K0.Value = val;
                case 'SigL', app.Sld_SigL.Value = val;
                case 'KT', app.Sld_KT.Value = val;
                case 'SigT', app.Sld_SigT.Value = val;
                case 'H', app.Sld_H.Value = val;
                case 'L', app.Sld_L.Value = val;
            end
            app.updatePlots();
        end

        % 4. Callback: Limits Changed
        function onLimitChange(app, ~, tag)
            switch tag
                case 'K0', sld=app.Sld_K0; mi=app.Edit_K0_Min.Value; ma=app.Edit_K0_Max.Value;
                case 'SigL', sld=app.Sld_SigL; mi=app.Edit_SigL_Min.Value; ma=app.Edit_SigL_Max.Value;
                case 'KT', sld=app.Sld_KT; mi=app.Edit_KT_Min.Value; ma=app.Edit_KT_Max.Value;
                case 'SigT', sld=app.Sld_SigT; mi=app.Edit_SigT_Min.Value; ma=app.Edit_SigT_Max.Value;
                case 'H', sld=app.Sld_H; mi=app.Edit_H_Min.Value; ma=app.Edit_H_Max.Value;
                case 'L', sld=app.Sld_L; mi=app.Edit_L_Min.Value; ma=app.Edit_L_Max.Value;
            end
            if mi >= ma, ma = mi + 1; end
            sld.Limits = [mi ma];
            sld.MajorTicks = linspace(mi, ma, 5);
            app.updatePlots();
        end

        % 5. Sync Helper
        function syncValueBox(app, tag, val)
             switch tag
                case 'K0', app.Edit_K0_Val.Value = val;
                case 'SigL', app.Edit_SigL_Val.Value = val;
                case 'KT', app.Edit_KT_Val.Value = val;
                case 'SigT', app.Edit_SigT_Val.Value = val;
                case 'H', app.Edit_H_Val.Value = val;
                case 'L', app.Edit_L_Val.Value = val;
            end
        end

        % 6. Main Plot Update
        function updatePlots(app)
            app.updateMaterialPlot();
            app.update3DPreview();
            app.updateResidualPlots(); % Questa riga attiva i nuovi grafici
        end

        function updateMaterialPlot(app)
            E = app.Edit_E.Value; Sy = app.Edit_Sy.Value;
            model = app.Drop_Model.Value;
            p1 = app.Edit_Par1.Value; p2 = app.Edit_Par2.Value; H_kin = app.Edit_Hkin.Value; 

            % Percorso di carico: Trazione -> Scarico -> Compressione
            steps_load = linspace(0, 0.025, 100);
            steps_unload = linspace(0.025, -0.025, 200); % Allunghiamo il ritorno per vedere bene Bauschinger
            strain_path = [steps_load, steps_unload];
            
            % Array Storia
            sigma_hist = zeros(size(strain_path));
            alpha_hist = zeros(size(strain_path)); % Storia del Centro
            radius_hist = zeros(size(strain_path)); % Storia del Raggio
            
            eps_pl_cum = 0; alpha = 0;
            
            for i = 1:length(strain_path)
                eps_curr = strain_path(i);
                
                % Calcolo Isotropo (Raggio della superficie)
                if strcmp(model, 'Linear'), R_iso = p1 * eps_pl_cum; H_prime = p1; 
                elseif strcmp(model, 'Ludwik'), eff_eps = max(1e-9, eps_pl_cum); R_iso = p1 * (eff_eps ^ p2); H_prime = p1 * p2 * (eff_eps ^ (p2-1));
                elseif strcmp(model, 'Voce'), term = exp(-p2 * eps_pl_cum); R_iso = (p1 - Sy) * (1 - term); H_prime = p2 * (p1 - Sy) * term;
                end
                
                Current_Yield_Radius = Sy + R_iso;
                
                % Predittore Elastico
                if i > 1
                    d_eps = eps_curr - strain_path(i-1);
                    sigma_trial = sigma_hist(i-1) + E * d_eps;
                else
                    sigma_trial = E * eps_curr;
                end

                % Verifica Snervamento rispetto al centro Alpha corrente
                eta = sigma_trial - alpha; 
                f = abs(eta) - Current_Yield_Radius;
                
                if f > 0
                    % Correttore Plastico
                    denom = E + H_kin + H_prime;
                    d_lambda = f / denom; 
                    sign_eta = sign(eta);
                    
                    sigma = sigma_trial - d_lambda * E * sign_eta;
                    alpha = alpha + d_lambda * H_kin * sign_eta; % Aggiornamento Centro (Cinematico)
                    eps_pl_cum = eps_pl_cum + d_lambda;          % Aggiornamento Raggio (Isotropo)
                else
                    sigma = sigma_trial;
                end
                
                % Salvataggio Storia
                sigma_hist(i) = sigma;
                alpha_hist(i) = alpha;
                radius_hist(i) = Current_Yield_Radius;
            end
            
            % --- PLOTTING ---
            hold(app.Ax_Mat, 'off');  % Forza reset dello stato hold
            cla(app.Ax_Mat, 'reset'); % Pulisce completamente l'asse
            hold(app.Ax_Mat, 'on');   % Riattiva hold per i nuovi grafici sovrapposti
            
            % 1. Fascia Elastica (Area ammissibile corrente)
            % Disegniamo i limiti istantanei
            upper_bound = alpha_hist + radius_hist;
            lower_bound = alpha_hist - radius_hist;
            
            plot(app.Ax_Mat, strain_path*100, upper_bound, 'g:', 'LineWidth', 1, 'DisplayName', 'Yield Limits');
            plot(app.Ax_Mat, strain_path*100, lower_bound, 'g:', 'LineWidth', 1, 'HandleVisibility', 'off');
            
            % 2. Centro Cinematico (Backstress)
            plot(app.Ax_Mat, strain_path*100, alpha_hist, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Backstress (\alpha)');
            
            % 3. Stress Reale
            plot(app.Ax_Mat, strain_path*100, sigma_hist, 'b-', 'LineWidth', 2, 'DisplayName', 'Stress (\sigma)');
            
            app.Ax_Mat.Title.String = 'Flow rule'; 
            xlabel(app.Ax_Mat, 'Strain [%]'); ylabel(app.Ax_Mat, 'Stress [MPa]');
            grid(app.Ax_Mat, 'on'); legend(app.Ax_Mat, 'Location', 'best');
        end



        function update3DPreview(app)
            % 1. Griglia di visualizzazione (2 metri di lunghezza)
            W = app.Edit_W.Value;
            [X, Y] = meshgrid(linspace(0, 2000, 150), linspace(-W/2, W/2, 80));
            
            % 2. Geometria della Curvatura (Coil Set di Input)
            % Leggiamo direttamente lo slider K0
            K0 = app.Sld_K0.Value * 1e-3; 
            
            % if abs(K0) > 1e-9
            %     % Usiamo la parabola (approssimazione corretta per piccoli spostamenti)
            %     % per evitare errori di numeri complessi su curvature elevate
            %     Z_Coil = 0.5 * K0 * X.^2;
            % else
            %     Z_Coil = 0;
            % end

            % Calcolo geometria circolare esatta con protezione numeri complessi
            if abs(K0) > 1e-9
                R = 1/K0;
                % Usiamo max(0, ...) per evitare radici di numeri negativi
                Z_Coil = R - sign(R) * sqrt(max(0, R^2 - X.^2));
                
                % Opzionale: "Nascondi" i punti oltre il raggio (dove la lamiera si chiuderebbe)
                Z_Coil(X > abs(R)) = NaN; 
            else
                Z_Coil = 0;
            end

            % 3. Geometria delle Onde (Difetti di planarità)
            H = app.Sld_H.Value;
            L = app.Sld_L.Value; if L <= 0, L = 500; end
            
            y_norm_sq = (2*Y/W).^2;
            switch app.Drop_WaveType.Value
                case 'Edge Waves',      prof = y_norm_sq;
                case 'Center Buckles',  prof = (1 - y_norm_sq);
                otherwise,              prof = (y_norm_sq - 0.5); % Balanced
            end
            
            Z_Wave = (H / 2) * prof .* sin(2*pi*X/L);
            
            % 4. Superficie Totale
            Z_tot = Z_Coil + Z_Wave;

            % 5. Rendering con Spessore Reale (per visualizzazione view [0,0])
            t = app.Edit_t.Value;
            cla(app.Ax_3D); hold(app.Ax_3D, 'on');

            % 6. Top (Estradosso) e Bottom (Intradosso) offsettati di t/2
            surf(app.Ax_3D, X, Y, Z_tot + t/2, Z_Wave, 'EdgeColor', 'none', 'FaceColor', 'interp');
            surf(app.Ax_3D, X, Y, Z_tot - t/2, Z_Wave, 'EdgeColor', 'none', 'FaceColor', 'interp', 'FaceAlpha', 0.5);
            % Chiusura bordi laterali (per vedere lo spessore dal lato)
            surf(app.Ax_3D, [X(1,:); X(1,:)], [Y(1,:); Y(1,:)], [Z_tot(1,:)-t/2; Z_tot(1,:)+t/2], 'FaceColor', 'k', 'FaceAlpha', 0.1, 'EdgeColor', 'none');
            surf(app.Ax_3D, [X(end,:); X(end,:)], [Y(end,:); Y(end,:)], [Z_tot(end,:)-t/2; Z_tot(end,:)+t/2], 'FaceColor', 'k', 'FaceAlpha', 0.1, 'EdgeColor', 'none');


            % % 6. Rendering of infinitesimal sheet thickness (Colorazione basata sull'ampiezza dell'onda per contrasto)
            % surf(app.Ax_3D, X, Y, Z_tot, Z_Wave, 'EdgeColor', 'none', 'FaceColor', 'interp');

            % Setup Estetico
            axis(app.Ax_3D, 'equal'); axis(app.Ax_3D, 'tight'); view(app.Ax_3D, [-45 30]);
            colormap(app.Ax_3D, 'jet'); camlight(app.Ax_3D, 'headlight'); lighting(app.Ax_3D, 'gouraud');
            grid(app.Ax_3D, 'on');
            title(app.Ax_3D, sprintf('Initial Sheet Geometry | K_0: %.4f', app.Sld_K0.Value));
        end

        function [i_unit, col] = calculateFlatness(app)
            H = app.Sld_H.Value; L = app.Sld_L.Value;
            if L <= 0, i_unit = 0; col = [0 0.5 0]; return; end
            i_unit = (H/L)^2 * 246760;
            if i_unit < 5, col = [0 0.7 0];
            elseif i_unit < 20, col = [0.8 0.8 0];
            elseif i_unit < 42, col = [0.9 0.5 0];
            else, col = [1 0 0]; end
        end

        function updateResidualPlots(app)
            t = app.Edit_t.Value; z = linspace(-t/2, t/2, 50);
            sigL = app.Sld_SigL.Value;
            % Plot Longitudinale
            cla(app.Ax_SigL); plot(app.Ax_SigL, (z/(t/2))*sigL, z, 'b', 'LineWidth', 2);
            grid(app.Ax_SigL,'on'); title(app.Ax_SigL, 'Long. Stress (z)');
            
            W = app.Edit_W.Value; y = linspace(-W/2, W/2, 50);
            sigT = app.Sld_SigT.Value;
            % Plot Trasversale
            cla(app.Ax_SigT); plot(app.Ax_SigT, y, sigT*((2*y/W).^2 - 0.5), 'r', 'LineWidth', 2);
            grid(app.Ax_SigT,'on'); title(app.Ax_SigT, 'Trans. Stress (y)');
        end

        function saveSheet(app)
            Sheet.Mat.E = app.Edit_E.Value; Sheet.Mat.Sy = app.Edit_Sy.Value; Sheet.Mat.Rm = app.Edit_Rm.Value;
            Sheet.Mat.Model = app.Drop_Model.Value;
            Sheet.Mat.P1 = app.Edit_Par1.Value; Sheet.Mat.P2 = app.Edit_Par2.Value;
            Sheet.Mat.H_kin = app.Edit_Hkin.Value;
            Sheet.Geo.t = app.Edit_t.Value; Sheet.Geo.W = app.Edit_W.Value;
            
            Sheet.Defects.K0_Geo = app.Sld_K0.Value * 1e-3; 
            Sheet.Defects.Sig_Long = app.Sld_SigL.Value;
            Sheet.Defects.K_Trans_Geo = app.Sld_KT.Value * 1e-3;
            Sheet.Defects.Sig_Trans = app.Sld_SigT.Value;
            Sheet.Defects.H_mm = app.Sld_H.Value; 
            Sheet.Defects.L_mm = app.Sld_L.Value;
            Sheet.Defects.WaveType = app.Drop_WaveType.Value; % Salva il tipo di onda
            [i_unit, ~] = app.calculateFlatness(); 
            Sheet.Defects.I_Units = i_unit;
            Sheet.State.Alpha_Final = zeros(51, 1);
            Sheet.State.Eps_Pl_Final = zeros(51, 1);
            Sheet.State.Sigma_Res = zeros(51, 1);
            
            [file, path] = uiputfile('*.sheet', 'Save Sheet Specification');
            if isequal(file,0), return; end
            save(fullfile(path, file), 'Sheet');
            uialert(app.ControlFigure, sprintf('Sheet saved successfully!\nFlatness: %.1f I-Units', i_unit), 'Success');
        end

        function updateFieldsVisibility(app)
            model = app.Drop_Model.Value;
            switch model
                case 'Linear', app.Lbl_Par1.Text = 'H_iso (Modulus):'; app.Lbl_Par2.Text = '-'; app.Edit_Par2.Enable = 'off';
                case 'Ludwik', app.Lbl_Par1.Text = 'K (Strength):'; app.Lbl_Par2.Text = 'n (Exponent):'; app.Edit_Par2.Enable = 'on';
                case 'Voce', app.Lbl_Par1.Text = 'S_sat (Saturation):'; app.Lbl_Par2.Text = 'b (Rate):'; app.Edit_Par2.Enable = 'on';
            end
        end

        function onModelChange(app)
            app.updateFieldsVisibility(); app.updatePlots();
        end
    end

    methods (Access = public)
        function app = SheetSpecApp
            % ============================================================
            %  1. CONTROL WINDOW (Input) - 2x2 Matrix Configuration
            % ============================================================
            app.ControlFigure = uifigure('Name', 'Sheet Spec - CONTROLS', ...
                'Position', [50 100 850 700], ... 
                'CloseRequestFcn', @(s,e) app.delete());
            
            % Main Grid: 2 rows x 2 columns
            app.GridControls = uigridlayout(app.ControlFigure, [2, 2]); 
            app.GridControls.RowHeight = {'1x', '0.5x'};
            app.GridControls.ColumnWidth = {'1x', '1x'};
            app.GridControls.Padding = [15 15 15 15];
            app.GridControls.RowSpacing = 15;
            app.GridControls.ColumnSpacing = 15;

            % --- QUADRANT (1,1): MATERIAL PANEL ---
            app.Pnl_Mat = uipanel(app.GridControls, 'Title', '1. Material & Metallurgy');
            app.Pnl_Mat.Layout.Row = 1; 
            app.Pnl_Mat.Layout.Column = 1;
            
            gl_m = uigridlayout(app.Pnl_Mat, [9, 2]);
            gl_m.RowHeight = {25, 25, 25, 25, 25, 25, 25, 25, 40};
            
            uilabel(gl_m,'Text','E [MPa]:'); app.Edit_E=uieditfield(gl_m,'numeric','Value',210000,'ValueChangedFcn',@(s,e)app.updatePlots());
            uilabel(gl_m,'Text','Yield Sy [MPa]:'); app.Edit_Sy=uieditfield(gl_m,'numeric','Value',300,'ValueChangedFcn',@(s,e)app.updatePlots());
            uilabel(gl_m,'Text','UTS Rm [MPa]:'); app.Edit_Rm=uieditfield(gl_m,'numeric','Value',450,'ValueChangedFcn',@(s,e)app.updatePlots());
            uilabel(gl_m,'Text','Thickness [mm]:'); app.Edit_t=uieditfield(gl_m,'numeric','Value',6,'ValueChangedFcn',@(s,e)app.updatePlots());
            uilabel(gl_m,'Text','Width [mm]:'); app.Edit_W=uieditfield(gl_m,'numeric','Value',1500,'ValueChangedFcn',@(s,e)app.updatePlots());
            uilabel(gl_m,'Text','Hardening Model:'); app.Drop_Model = uidropdown(gl_m, 'Items', {'Linear','Ludwik','Voce'}, 'ValueChangedFcn', @(s,e) app.onModelChange());
            app.Lbl_Par1=uilabel(gl_m,'Text','H_iso:'); app.Edit_Par1=uieditfield(gl_m,'numeric','Value',1000,'ValueChangedFcn',@(s,e)app.updatePlots());
            app.Lbl_Par2=uilabel(gl_m,'Text','-'); app.Edit_Par2=uieditfield(gl_m,'numeric','Value',0,'ValueChangedFcn',@(s,e)app.updatePlots());
            app.Lbl_Hkin=uilabel(gl_m,'Text','H_kin:'); app.Edit_Hkin=uieditfield(gl_m,'numeric','Value',2000,'ValueChangedFcn',@(s,e)app.updatePlots());

            % --- QUADRANT (2,1): LONGITUDINAL PANEL ---
            app.Pnl_Long = uipanel(app.GridControls, 'Title', '2. Longitudinal Defects (Coil Set)');
            app.Pnl_Long.Layout.Row = 2; 
            app.Pnl_Long.Layout.Column = 1;
            
            gl_l = uigridlayout(app.Pnl_Long, [2, 1]); 
            gl_l.RowHeight = {'1x', '1x'};
            
            app.createSmartSlider(gl_l, 1, 'Longitudinal Curvature K0 [1/m]', -5, 5, -0.2, 'K0');
            app.createSmartSlider(gl_l, 2, 'Surface Residual Stress [MPa]', -300, 300, -100, 'SigL');

            % --- QUADRANT (1,2): TRANSVERSE PANEL & WAVE TYPE ---
            app.Pnl_Trans = uipanel(app.GridControls, 'Title', '3. Transverse Defects (Crossbow & Waves)');
            app.Pnl_Trans.Layout.Row = 1; 
            app.Pnl_Trans.Layout.Column = 2;
            
            gl_t = uigridlayout(app.Pnl_Trans, [5, 1]); % 5 rows to include Wave Type
            gl_t.RowHeight = {'1x', '1x', '1x', '1x', 40};

            app.createSmartSlider(gl_t, 1, 'Geometric Crossbow [1000/m]', -5, 5, 0.5, 'KT');
            app.createSmartSlider(gl_t, 2, 'Crossbow Stress [MPa]', -300, 300, 50, 'SigT');
            app.createSmartSlider(gl_t, 3, 'Wave Height H [mm]', 0, 50, 5, 'H');
            app.createSmartSlider(gl_t, 4, 'Wave Pitch L [mm]', 100, 2000, 500, 'L');
            
            % Move Wave Type Group here
            subG_W = uigridlayout(gl_t, [1, 2]); subG_W.Layout.Row = 5; subG_W.ColumnWidth = {'fit','1x'};
            uilabel(subG_W, 'Text', 'Wave Pattern:');
            app.Drop_WaveType = uidropdown(subG_W, 'Items', {'Edge Waves', 'Center Buckles', 'Balanced (Mixed)'}, 'Value', 'Edge Waves', 'ValueChangedFcn', @(s,e) app.updatePlots());


            % --- QUADRANT (2,2): SAVE ACTION ---
            BtnGrid = uigridlayout(app.GridControls, [3, 1]);
            BtnGrid.Layout.Row = 2; 
            BtnGrid.Layout.Column = 2;
            BtnGrid.RowHeight = {'1x', 80, '1x'};
            
            app.Btn_Save = uibutton(BtnGrid, 'Text', 'EXPORT .SHEET FILE', ...
                'BackgroundColor', [0 0.45 0.74], 'FontColor', 'w', 'FontWeight', 'bold', 'FontSize', 18, ...
                'ButtonPushedFcn', @(s,e) app.saveSheet());
            app.Btn_Save.Layout.Row = 2;


            % ============================================================
            %  2. VISUALIZATION WINDOW (Output)
            % ============================================================
            app.GraphFigure = uifigure('Name', 'Sheet Spec - VISUALIZATION', ...
                'Position', [920 100 950 700], ... 
                'Color', 'w'); 
            
            app.GridGraphs = uigridlayout(app.GraphFigure, [2, 3]); 
            app.GridGraphs.RowHeight = {'1x', '1.5x'};
            app.GridGraphs.ColumnSpacing = 20; 
            app.GridGraphs.RowSpacing = 20;    
            
            % Row 1: Detail Charts
            app.Ax_Mat = uiaxes(app.GridGraphs);
            app.Ax_Mat.Layout.Row = 1; app.Ax_Mat.Layout.Column = 1;
            app.Ax_Mat.Title.String = 'Material Law';

            app.Ax_SigL = uiaxes(app.GridGraphs);
            app.Ax_SigL.Layout.Row = 1; app.Ax_SigL.Layout.Column = 2;
            app.Ax_SigL.Title.String = 'Z-Stress Profile (Long)';

            app.Ax_SigT = uiaxes(app.GridGraphs);
            app.Ax_SigT.Layout.Row = 1; app.Ax_SigT.Layout.Column = 3;
            app.Ax_SigT.Title.String = 'Y-Stress Profile (Trans)';

            % Row 2: 3D Preview
            app.Ax_3D = uiaxes(app.GridGraphs);
            app.Ax_3D.Layout.Row = 2; app.Ax_3D.Layout.Column = [1 3];
            app.Ax_3D.Title.String = '3D Sheet Surface Preview';
            

            % Finalize
            app.onModelChange(); 
            figure(app.ControlFigure); 
        end
        
        % Metodo Distruttore (deve essere PUBLIC)
        function delete(app)
            % Elimina le figure se sono ancora valide
            if isvalid(app.GraphFigure), delete(app.GraphFigure); end
            if isvalid(app.ControlFigure), delete(app.ControlFigure); end
        end
    end
end