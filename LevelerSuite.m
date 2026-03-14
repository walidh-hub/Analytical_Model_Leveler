classdef LevelerSuite < matlab.apps.AppBase

    % Properties
    properties (Access = public)
        UIFigure      matlab.ui.Figure
        GridMain      matlab.ui.container.GridLayout
        LblTitle      matlab.ui.control.Label
        BtnGen        matlab.ui.control.Button
        BtnSim        matlab.ui.control.Button
        LblCredit     matlab.ui.control.Label
    end

    methods (Access = private)
        
        % Callback: Apre il Generatore
        function openGenerator(app)
            % Lancia la classe SheetSpecApp
            SheetSpecApp; 
        end

        % Callback: Apre il Simulatore
        function openSimulator(app)
            % Lancia la classe LevelerApp
            LevelerApp;
        end
    end

    methods (Access = public)

        function app = LevelerSuite
            % Create UIFigure and components
            app.UIFigure = uifigure('Name', 'Leveler Pro Suite 2025', 'Position', [100 100 500 400]);
            app.UIFigure.Resize = 'off';
            
            app.GridMain = uigridlayout(app.UIFigure, [4, 1]);
            app.GridMain.RowHeight = {'1x', '1x', '1x', 30};
            app.GridMain.Padding = [40 40 40 40];
            app.GridMain.RowSpacing = 20;

            % Titolo
            app.LblTitle = uilabel(app.GridMain, 'Text', 'LEVELER PRO SUITE', ...
                'HorizontalAlignment', 'center', 'FontSize', 24, 'FontWeight', 'bold', ...
                'FontColor', [0 0.45 0.74]);
            app.LblTitle.Layout.Row = 1;

            % Tasto 1: Generatore
            app.BtnGen = uibutton(app.GridMain, 'Text', '1. SHEET GENERATOR (Input Spec)', ...
                'FontSize', 16, 'FontWeight', 'bold', 'Icon', 'matlab_icon.png', ...
                'BackgroundColor', [0.9 0.9 0.9], ...
                'ButtonPushedFcn', @(s,e) app.openGenerator());
            app.BtnGen.Layout.Row = 2;

            % Tasto 2: Simulatore
            app.BtnSim = uibutton(app.GridMain, 'Text', '2. LEVELER SIMULATOR (Process)', ...
                'FontSize', 16, 'FontWeight', 'bold', ...
                'BackgroundColor', [0 0.6 0], 'FontColor', 'w', ...
                'ButtonPushedFcn', @(s,e) app.openSimulator());
            app.BtnSim.Layout.Row = 3;

            % Footer
            app.LblCredit = uilabel(app.GridMain, 'Text', 'Powered by SmartLeveler.it', ...
                'HorizontalAlignment', 'center', 'FontColor', [0.6 0.6 0.6]);
            app.LblCredit.Layout.Row = 4;
        end
    end
end