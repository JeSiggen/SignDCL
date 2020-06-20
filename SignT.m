classdef SignT<handle
%% SignT - A GUI to perform mouse tracking.
%
% Uses common image processing methods to retrieve mouse contour, center of
% gravity, as well as a motion measure (global change in pixels) in an
% efficient and reliable way for large batches, with standardized outputs.
%
%       - Works on both RGB and greyscale movies (incl. thermal)
%       - Can process a background image to remove from each individual
%       frame to get a better tracking (automatic or manual selection of
%       the frames to use, different methods to process the resulting
%       background)
%       - Uses the parallel computing toolbox to increase processing speed
%       (several movies can be "prepared" and then batch-processed, in
%       parallel; up to 10-15 can be processed at once, usually taking as
%       much time as the duration of one movie, but if more are prepared
%       and launched, they will automatically be processed anyway, it will
%       just take one/several more rounds)
%       
%
% The current version has not been tested for compatibility and
% dependencies; in particular, it might not run under MATLAB versions
% older than R2018a. 
%
%
% Future implementations/changes:
%       - Expand the manual
%       - Make the overall code less dependent on the recording system
%       - Take into account major dependencies/versions problems, and test 
%       the compatibility to estimate the requirements
%       - Use parallel computing to process frames from a single movie in
%       parallel
%       - Implement dynamic thresholding for thermal movies 
%       (if the temperature changes, the threshold can be suboptimal for 
%       some periods)
%       - Implement limitation on the resources used -sometimes we might
%       want to use 100% of the available CPU, but on a server, it might be
%       nice to leave some resources to other people
%       - Improve some aspects of the code to make it a bit lighter and 
%       easier to follow and modify (esp. on the properties side)
%       - Test with different types of data (larger movie resolution might
%       decrease the plotting performance)
%
%     Copyright (C) 2019 Jérémy Signoret-Genest, DefenseCircuitsLab
%     Initial version: original code 2018, current form early 2019
%     Current version: 20/06/2020     
%
%     Changelog (only from 23/05/2020):
%       - 20/06/2020:
%           . Corrected performance issues (tracking sometimes taking 2x
%           the normal time) by 
%       - 15/06/2020:
%           . Corrected a bug that led to an error when some frames didn't
%           yield any satisfactory tracking
%       - 06/06/2020:
%           . Movie slider had a lot of intertia, and also produced some
%           jumps; same problem as corrected for the frame update:
%           implemented another control to force to wait for the current
%           frame change to be complete before updating again during
%           sliding
%       - 05/06/2020: 
%           . Updated description, added some annotation, improved
%           some pieces of code
%           . Added font scaling for different screen resolutions
%           . Stored some elements in parameters to prevent them
%           from being generated/processed for each frame
%           . Updating the current frame (e.g. after changing a parameter)
%           sometimes led to actually changing the current frame time 
%           because the update was called during processing: added a 
%           logical toggle switch to update only when the previous update 
%           was complete
%       - 23/05/2020: 
%           . added calibration option; the coordinates themselves are 
%           saved, in case we want to use calibration after correcting for 
%           camera distorsion
%
%     This program is free software: you can redistribute it and/or modify
%     it under the terms of the GNU General Public License as published by
%     the Free Software Foundation, either version 3 of the License, or
%     (at your option) any later version.
%
%     This program is distributed in the hope that it will be useful,
%     but WITHOUT ANY WARRANTY; without even the implied warranty of
%     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%     GNU General Public License for more details.
%
%     You should have received a copy of the GNU General Public License
%     along with this program.  If not, see <https://www.gnu.org/licenses/>.

    properties(SetAccess = private, GetAccess = public)
        Basename
        BatchFiles = {};
        CurrentFile
        Parameters
        TrackingLogFile
    end
    
    properties(SetAccess = private, GetAccess = public, Hidden = true)
        BackGround
        BackGroundFigure
        BackGroundFrameLines
        BackGroundMovie
        BackGroundSliderLine
        BackGroundSliderPrctileLine
        BackGroundSub
        BackGroundSubMovie
        BackGroundSubMarkers
        BackGroundSubSlider
        BackGroundSubSliderPrctile
        CenterPlot
        ContourPlot
        CurrentImageMode
        CurrentTime = 0;
        DefaultParameters
        Dragging = false;
        Figure
        FontScaling
        FramePlot
        FrameRate
        Handles
        HandlesBG
        Initialized = false;
        LastParameters
        Mask
        Movie
        OutsideMask
        Play = false;
        PrePlayState
        Refractory = false;
        Shape
        SliderLine
        Speed = 1;
        SpeedText
        StartPath
        SubMovie
        SubSlider
        UIResponsiveness
    end
    
methods
     % Constructor
        function obj = SignT
            %% Parameters
                % This system makes our lives easier when handling all the
                % parameters at once (restoring, keeping in memory, saving),
                % regardless of how the list may change in the future; 
                % the idea is also to save/load them from/to a file someday
                obj.Parameters.Names = {
                    'BackGround',
                    'Calibration',
                    'Channel',
                    'FilterSizeEnable',
                    'Mask',
                    'MC1Enable',
                    'MC2Enable',
                    'MO1Enable',
                    'FilterSize',
                    'MC1Value',
                    'MC2Value',
                    'MO1Value',
                    'OutsideMask',
                    'ReflectionPenalty',
                    'MouseRelativeIntensity',
                    'Shape',
                    'SmoothContourEnable',
                    'SmoothContourValue',
                    'StructuringElement',
                    'Threshold',
                    'VideoMode',
                    };
                obj.DefaultParameters.BackGround.Enable = false;
                obj.DefaultParameters.BackGround.Image = [];
                obj.DefaultParameters.BackGround.Mode = 'Median';
                obj.DefaultParameters.BackGround.FramesNum = 50;
                obj.DefaultParameters.BackGround.PickedTimes = [];
                obj.DefaultParameters.BackGround.Prctile = 50;
                obj.DefaultParameters.BackGround.Substract = 0;
                obj.DefaultParameters.BackGround.SubstractMain = 0;
                obj.DefaultParameters.Calibration.Length = [];
                obj.DefaultParameters.Calibration.Line = [];
                obj.DefaultParameters.Channel = 'R';
                obj.DefaultParameters.Threshold = 80;
                obj.DefaultParameters.ReflectionPenalty = 1;
                obj.DefaultParameters.MC1Value = 5;
                obj.DefaultParameters.FilterSize = 10;
                obj.DefaultParameters.MC2Value = 7;
                obj.DefaultParameters.MO1Value = 7;
                obj.DefaultParameters.SmoothContourValue = 10;
                obj.DefaultParameters.MC1Enable = true;
                obj.DefaultParameters.FilterSizeEnable = true;
                obj.DefaultParameters.MC2Enable = true;
                obj.DefaultParameters.MO1Enable = true;
                obj.DefaultParameters.MouseRelativeIntensity = 'Low';
                obj.DefaultParameters.Shape = [];
                obj.DefaultParameters.Mask = [];
                obj.DefaultParameters.OutsideMask = [];
                obj.DefaultParameters.VideoMode = 'RGB';
                obj.DefaultParameters.StructuringElement.MO1i = strel('disk',2);
                obj.DefaultParameters.StructuringElement.MC1 = strel('disk', obj.DefaultParameters.MC1Value);
                obj.DefaultParameters.StructuringElement.MC2 = strel('disk', obj.DefaultParameters.MC2Value);
                obj.DefaultParameters.StructuringElement.MO1 = strel('disk', obj.DefaultParameters.MO1Value);
                obj.DefaultParameters.SmoothContourEnable = true;
                for P = 1 : length(obj.Parameters.Names),
                    obj.Parameters.(obj.Parameters.Names{P}) =  obj.DefaultParameters.(obj.Parameters.Names{P});
                end
                
    %% Initialize the GUI
    % NB: Most of the "Set" buttons are not needed per se, but since the
    % callback from e.g. an edit box is triggered upon clicking somewhere,
    % the "Set" buttons provide an easy way to make sure the user will
    % activate the corresponding callback (they don't have their own
    % callback functions)
    
    % Figure
    Scrsz = get(0,'ScreenSize');
    obj.Figure = figure('Position',[Scrsz(3)/10 45 4/5*Scrsz(3) Scrsz(4)-75],'MenuBar','none');
    
    % Font scaling for different screen resolutions
    obj.FontScaling = min([Scrsz(3)/1920,Scrsz(4)/1080]);

    % Movie axes
    obj.SubMovie = subplot('Position',[0.075 0.4 0.4167 0.5161]);
    obj.SubMovie.XColor = 'none';
    obj.SubMovie.YColor = 'none';
    ButtonsXStart = 0.1425;
    
    % Player uicontrols
    obj.Handles.PlayButton = uicontrol('Style','pushbutton','String','Play','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.SetPlay},'Units','Normalized','Position',[ButtonsXStart+0.07 0.3 0.07 0.05]);
    obj.Handles.PauseButton = uicontrol('Style','pushbutton','String','Pause','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.PauseMovie},'Units','Normalized','Position',[ButtonsXStart+0.07*2 0.3 0.07 0.05]);
    obj.Handles.DecreaseRateButton = uicontrol('Style','pushbutton','String','Slower','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.DecreaseFrameRate},'Units','Normalized','Position',[ButtonsXStart 0.3 0.07 0.05]);
    obj.Handles.IncreaseRateButton = uicontrol('Style','pushbutton','String','Faster','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.IncreaseFrameRate},'Units','Normalized','Position',[ButtonsXStart+0.07*3 0.3 0.07 0.05]);
   
    % Slider
    obj.SubSlider = subplot('Position',[obj.SubMovie.Position(1) 0.36 obj.SubMovie.Position(3) 0.03]);
    obj.SubSlider.Color = [0.975 0.975 0.975];
    obj.SliderLine = plot([0 0],[0 1],'Color','k','LineWidth',3.5,'ButtonDownFcn',{@(~,~)obj.Slide});
    obj.SubSlider.YColor = 'none';
    obj.SubSlider.XColor = 'none';
    obj.SubSlider.XLim = [-0.5 1.5];
    obj.SubSlider.YLim = [0 1];
    if ~verLessThan('matlab','9.5')
        obj.SubSlider.Toolbar.Visible = 'off';
        disableDefaultInteractivity(obj.SubSlider);
    end
    
    % Context limit UI
    obj.Handles.LimitsLegend = uicontrol('Style','text','String','Limits','FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
        'Units','Normalized','Position',[ButtonsXStart-0.1 obj.SubMovie.Position(2)+obj.SubMovie.Position(4) 0.085 0.04],'HorizontalAlignment','right');
    obj.Handles.CircleButton = uicontrol('Style','pushbutton','String','Circle','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.CircleButtonCB},'Units','Normalized','Position',[ButtonsXStart obj.SubMovie.Position(2)+obj.SubMovie.Position(4)+0.005 0.07 0.05]);
    obj.Handles.FreeButton = uicontrol('Style','pushbutton','String','Polygon','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.FreeButtonCB},'Units','Normalized','Position',[ButtonsXStart+0.07 obj.SubMovie.Position(2)+obj.SubMovie.Position(4)+0.005 0.07 0.05]);
    obj.Handles.DeleteButton = uicontrol('Style','pushbutton','String','Delete','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.DeleteButtonCB},'Units','Normalized','Position',[ButtonsXStart+0.07*2  obj.SubMovie.Position(2)+obj.SubMovie.Position(4)+0.005 0.07 0.05]);
    
    % Calibration UI
    obj.Handles.CalibrationLegend = uicontrol('Style','text','String','Calibration','FontSize',obj.FontScaling*13,'FontName','Arial','FontWeight','bold',...
        'Units','Normalized','Position',[ButtonsXStart+0.07*3 obj.SubMovie.Position(2)+obj.SubMovie.Position(4)+0.04 0.14 0.025],'HorizontalAlignment','center');
    obj.Handles.CalibrationDraw = uicontrol('Style','pushbutton','String','Draw','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.DrawCalibrationCB},'Units','Normalized','Position',[ButtonsXStart+0.07*3  obj.SubMovie.Position(2)+obj.SubMovie.Position(4)+0.005 0.07 0.04]);
    obj.Handles.CalibrationEdit = uicontrol('Style','edit','String','','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.EditCalibrationCB},'Units','Normalized','Position',[ButtonsXStart+0.07*4  obj.SubMovie.Position(2)+obj.SubMovie.Position(4)+0.005 0.045 0.04]);
    obj.Handles.CalibrationUnitLegend = uicontrol('Style','text','String','cm','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Units','Normalized','Position',[ButtonsXStart+0.07*4+0.05  obj.SubMovie.Position(2)+obj.SubMovie.Position(4)+0.005 0.025 0.03],'HorizontalAlignment','left');

    % CLim
    obj.Parameters.HotWhite = load('HotWhite');
    obj.Parameters.HotWhite = obj.Parameters.HotWhite.HotWhite;
    obj.Handles.SubCLim = subplot('Position',[ButtonsXStart 0.23 0.07*4 0.04]);
    obj.Handles.SubCLim.YColor = 'none';
    obj.Handles.SubCLim.XColor = 'none';
    obj.Handles.SubCLim.XLim = [-0.5 255.5];
    obj.Handles.SubCLim.YLim = [0 1];
    hold(obj.Handles.SubCLim,'on');
    if ~verLessThan('matlab','9.5')
        obj.Handles.SubCLim.Toolbar.Visible = 'off';
        disableDefaultInteractivity(obj.Handles.SubCLim);
    end
    SubCLimLegend = uicontrol('Style','text','String','CLim','FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
        'Units','Normalized','Position',[ButtonsXStart-0.085 0.22 0.07 0.04],'HorizontalAlignment','right');
    obj.Handles.LowCLimLine = plot([0 0],[0 1],'Color','k','LineWidth',3.5,'ButtonDownFcn',{@(~,~)obj.SlideLowCLim},'Parent',obj.Handles.SubCLim);
    obj.Handles.HighCLimLine = plot([255 255],[0 1],'Color','k','LineWidth',3.5,'ButtonDownFcn',{@(~,~)obj.SlideHighCLim},'Parent',obj.Handles.SubCLim);
    obj.Handles.LowCLimEdit = uicontrol('Style','edit',...
        'String','0','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.LowCLimEditCB},'Units','Normalized','Position',[ButtonsXStart 0.17 0.07 0.05]);
    obj.Handles.HighCLimEdit = uicontrol('Style','edit',...
        'String','255','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.HighCLimEditCB},'Units','Normalized','Position',[ButtonsXStart+0.07 0.17 0.07 0.05]);
    obj.Handles.SetCLim = uicontrol('Style','pushbutton','String','Set','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.SetCLimCB},'Units','Normalized','Position',[ButtonsXStart+0.07*2 0.17 0.07 0.05]);
    obj.Handles.ResetCLim = uicontrol('Style','pushbutton','String','Reset','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.ResetCLimCB},'Units','Normalized','Position',[ButtonsXStart+0.07*3 0.17 0.07 0.05]);
    
    % Channel
    ChannelLegend = uicontrol('Style','text','String','Channel used','FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
        'Units','Normalized','Position',[ButtonsXStart-0.1 0.085 0.085 0.04],'HorizontalAlignment','right');
    obj.Handles.RChannel = uicontrol('Style','togglebutton','String','R','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.RChannelCB},'Units','Normalized','Position',[ButtonsXStart 0.09 0.07 0.05]);
    obj.Handles.GChannel = uicontrol('Style','togglebutton','String','G','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.GChannelCB},'Units','Normalized','Position',[ButtonsXStart+0.07 0.09 0.07 0.05]);
    obj.Handles.BChannel = uicontrol('Style','togglebutton','String','B','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.BChannelCB},'Units','Normalized','Position',[ButtonsXStart+0.07*2 0.09 0.07 0.05]);
    obj.Handles.GreyChannel = uicontrol('Style','togglebutton','String','Grey','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.GreyChannelCB},'Units','Normalized','Position',[ButtonsXStart+0.07*3 0.09 0.07 0.05]);
    
    % Colormaps
    ColormapLegend = uicontrol('Style','text','String','Colormap','FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
        'Units','Normalized','Position',[ButtonsXStart-0.085 0.025 0.07 0.04],'HorizontalAlignment','right');
    obj.Handles.JetButton = uicontrol('Style','togglebutton','String','Jet','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.JetCB},'Units','Normalized','Position',[ButtonsXStart 0.03 0.07 0.05]);
    obj.Handles.ParulaButton = uicontrol('Style','togglebutton','String','Parula','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.ParulaCB},'Units','Normalized','Position',[ButtonsXStart+0.07*1 0.03 0.07 0.05]);
    obj.Handles.HotWhiteButton = uicontrol('Style','togglebutton','String','Hot white','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.HWCB},'Units','Normalized','Position',[ButtonsXStart+0.07*2 0.03 0.07 0.05]);
    obj.Handles.OriginalButton = uicontrol('Style','togglebutton','String','Original','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.OriginalCB},'Units','Normalized','Position',[ButtonsXStart+0.07*3 0.03 0.07 0.05],...
        'Value',1);
    obj.Handles.Shape = [];
    
    % Background
    BackgroundLegend = uicontrol('Style','text','String','Background','FontSize',obj.FontScaling*18,'FontName','Arial','FontWeight','bold',...
        'Units','Normalized','Position',[0.55 0.95 0.15 0.04],'HorizontalAlignment','left');
    obj.Handles.BackGroundProcessButton = uicontrol('Style','pushbutton','String','Process','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.BackGroundProcessCB},'Units','Normalized','Position',[0.55 0.915 0.07 0.04]);
    obj.Handles.BackGroundImportButton = uicontrol('Style','pushbutton','String','Import','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Enable','off','Callback',{@(~,~)obj.Parameters.BackGround.ImageImportCB},'Units','Normalized','Position',[0.62 0.915 0.07 0.04]);
    obj.Handles.BackGroundEnable = uicontrol('Style','checkbox','String','Use (substract to frames)',...
        'Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.BackGroundEnableCB},'Units','Normalized','Position',[0.725 0.925 0.2 0.04],'HorizontalAlignment','left');
    obj.Handles.ShowSubstracted = uicontrol('Style','checkbox','String','Show substracted',...
        'Value',0,'FontSize',obj.FontScaling*13,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.ShowSubstractedCB},'Units','Normalized','Enable','off','Position',[0.75 0.905 0.2 0.03],'HorizontalAlignment','left');
    
    % Threshold
    ThresholdLegend = uicontrol('Style','text','String','Threshold','FontSize',obj.FontScaling*18,'FontName','Arial','FontWeight','bold',...
        'Units','Normalized','Position',[0.55 0.86 0.15 0.03],'HorizontalAlignment','left');
    obj.Handles.RelativeIntensityHigh = uicontrol('Style','checkbox','String','Track bright/high intensity objects','Value',0,'FontSize',obj.FontScaling*13,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.RelativeIntensityHighCB},'Units','Normalized','Position',[0.6 0.81 0.3 0.03],'HorizontalAlignment','left');
    obj.Handles.RelativeIntensityLow = uicontrol('Style','checkbox','String','Track dark/low intensity objects','Value',1,'FontSize',obj.FontScaling*13,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.RelativeIntensityLowCB},'Units','Normalized','Position',[0.6 0.835 0.3 0.03],'HorizontalAlignment','left');
    obj.Handles.SubThreshold = subplot('Position',[0.625 0.765 0.25 0.04]);
    obj.Handles.SubThreshold.Color = 'w';
    obj.Handles.SubThreshold.YColor = 'none';
    obj.Handles.SubThreshold.XColor = 'none';
    obj.Handles.SubThreshold.XLim = [-0.5 255.5];
    obj.Handles.SubThreshold.YLim = [0 1];
    hold(obj.Handles.SubThreshold,'on');
    if ~verLessThan('matlab','9.5')
        obj.Handles.SubThreshold.Toolbar.Visible = 'off';
        disableDefaultInteractivity(obj.Handles.SubThreshold);
    end
    obj.Handles.Threshold.Line = plot([obj.DefaultParameters.Threshold obj.DefaultParameters.Threshold],[0 1],'Color','k','LineWidth',3.5,'ButtonDownFcn',{@(~,~)obj.SliderThresholdCB},'Parent',obj.Handles.SubThreshold);
    obj.Handles.Threshold.Edit = uicontrol('Style','edit',...
        'String',num2str(obj.DefaultParameters.Threshold),'FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.ThresholdEditCB},'Units','Normalized','Position',[0.55 0.765 0.07 0.04]);
    obj.Handles.Threshold.Set = uicontrol('Style','pushbutton','String','Set','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.ThresholdEditCB},'Units','Normalized','Position',[0.88 0.765 0.07 0.04]);

    % Reflection penalty
    ReflectionLegend = uicontrol('Style','text','String','Reflection penalty','FontSize',obj.FontScaling*18,'FontName','Arial','FontWeight','bold',...
        'Units','Normalized','Position',[0.55 0.71 0.15 0.03],'HorizontalAlignment','left');
    obj.Handles.SubRP = subplot('Position',[0.625 0.665 0.25 0.04]);
    obj.Handles.SubRP.Color = 'w';
    obj.Handles.SubRP.YColor = 'none';
    obj.Handles.SubRP.XColor = 'none';
    obj.Handles.SubRP.XLim = [1 10];
    obj.Handles.SubRP.YLim = [0 1];
    hold(obj.Handles.SubRP,'on');
    if ~verLessThan('matlab','9.5')
        obj.Handles.SubRP.Toolbar.Visible = 'off';
        disableDefaultInteractivity(obj.Handles.SubRP);
    end
    obj.Handles.RP.Line = plot([obj.DefaultParameters.ReflectionPenalty obj.DefaultParameters.ReflectionPenalty],[0 1],'Color','k','LineWidth',3.5,'ButtonDownFcn',{@(~,~)obj.SliderRPCB},'Parent',obj.Handles.SubRP);
    obj.Handles.RP.Edit = uicontrol('Style','edit',...
        'String',num2str(obj.DefaultParameters.ReflectionPenalty),'FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.RPEditCB},'Units','Normalized','Position',[0.55 0.665 0.07 0.04]);
    obj.Handles.RP.Set = uicontrol('Style','pushbutton','String','Set','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.RPEditCB},'Units','Normalized','Position',[0.88 0.665 0.07 0.04]);
    
    % Image treatment
    ImageTreatmentLegend = uicontrol('Style','text','String','Mask treatment','FontSize',obj.FontScaling*18,'FontName','Arial','FontWeight','bold',...
        'Units','Normalized','Position',[0.55 0.6 0.15 0.04],'HorizontalAlignment','left');
    SELegend = uicontrol('Style','text','String','Size (px)','FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
        'Units','Normalized','Position',[0.8 0.605 0.07 0.025],'HorizontalAlignment','center');
    obj.Handles.MC1Value.CheckBox = uicontrol('Style','checkbox','String',' 1. Morphological closing','Value',1,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
        'Value',obj.DefaultParameters.MC1Enable,'Callback',{@(~,~)obj.MC1CB},'Units','Normalized','Position',[0.6 0.565 0.2 0.04],'HorizontalAlignment','left');
    obj.Handles.MC1Value.Edit = uicontrol('Style','edit','String',obj.DefaultParameters.MC1Value,'FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.MC1EditCB},'Units','Normalized','Position',[0.8 0.565 0.07 0.04],'HorizontalAlignment','center');
    obj.Handles.MC1Value.Set = uicontrol('Style','pushbutton','String','Set','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
        'Callback',{@(~,~)obj.MC1EditCB},'Units','Normalized','Position',[0.88 0.565 0.07 0.04]);
     
     obj.Handles.FilterSize.CheckBox = uicontrol('Style','checkbox','String',' 2. Size threshold','Value',1,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
         'Value',obj.DefaultParameters.FilterSizeEnable,'Callback',{@(~,~)obj.SFCB},'Units','Normalized','Position',[0.6 0.525 0.2 0.04],'HorizontalAlignment','left');
     obj.Handles.FilterSize.Edit = uicontrol('Style','edit','String',obj.DefaultParameters.FilterSize,'FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.SFEditCB},'Units','Normalized','Position',[0.8 0.525 0.07 0.04],'HorizontalAlignment','center');
     obj.Handles.FilterSize.Set = uicontrol('Style','pushbutton','String','Set','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.SFEditCB},'Units','Normalized','Position',[0.88 0.525 0.07 0.04]);
     
     obj.Handles.MC2Value.CheckBox = uicontrol('Style','checkbox','String',' 3. Morphological closing','Value',1,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
          'Value',obj.DefaultParameters.MC2Enable,'Callback',{@(~,~)obj.MC2CB},'Units','Normalized','Position',[0.6 0.485 0.2 0.04],'HorizontalAlignment','left');
     obj.Handles.MC2Value.Edit = uicontrol('Style','edit','String',obj.DefaultParameters.MC2Value,'FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.MC2EditCB},'Units','Normalized','Position',[0.8 0.485 0.07 0.04],'HorizontalAlignment','center');
     obj.Handles.MC2Value.Set = uicontrol('Style','pushbutton','String','Set','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.MC2EditCB},'Units','Normalized','Position',[0.88 0.485 0.07 0.04]);
     
     obj.Handles.MO1Value.CheckBox = uicontrol('Style','checkbox','String',' 4. Morphological opening','Value',1,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
          'Value',obj.DefaultParameters.MO1Enable,'Callback',{@(~,~)obj.MO1CB},'Units','Normalized','Position',[0.6 0.445 0.2 0.04],'HorizontalAlignment','left');
     obj.Handles.MO1Value.Edit = uicontrol('Style','edit','String',obj.DefaultParameters.MO1Value,'FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.MO1EditCB},'Units','Normalized','Position',[0.8 0.445 0.07 0.04],'HorizontalAlignment','center');
     obj.Handles.MO1Value.Set = uicontrol('Style','pushbutton','String','Set','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.MO1EditCB},'Units','Normalized','Position',[0.88 0.445 0.07 0.04]);
     
     % Contour treatment
     ContourTreatmentLegend = uicontrol('Style','text','String','Contour treatment','FontSize',obj.FontScaling*18,'FontName','Arial','FontWeight','bold',...
         'Units','Normalized','Position',[0.55 0.37 0.15 0.04],'HorizontalAlignment','left');
     obj.Handles.SmoothContour.CheckBox = uicontrol('Style','checkbox','String',' Smoothing',...
         'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
         'Value',obj.DefaultParameters.SmoothContourEnable,'Callback',{@(~,~)obj.SmoothContourCB},'Units','Normalized','Position',[0.6 0.335 0.2 0.04],'HorizontalAlignment','left');
     obj.Handles.SmoothContour.Edit = uicontrol('Style','edit',...
         'String',obj.DefaultParameters.SmoothContourValue,'FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.SmoothContourEditCB},'Units','Normalized','Position',[0.8 0.335 0.07 0.04],'HorizontalAlignment','center');
     obj.Handles.SmoothContour.Set = uicontrol('Style','pushbutton','String','Set','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.SmoothContourEditCB},'Units','Normalized','Position',[0.88 0.335 0.07 0.04]);
     
     % Status
     obj.Handles.ResetDefaultButton = uicontrol('Style','pushbutton','String','Restore to default','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.ResetDefaultCB},'Units','Normalized','Position',[0.75 0.25 0.175 0.04]);
     obj.Handles.RestorePreviousButton = uicontrol('Style','pushbutton','String','Restore as previous','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.ResetPreviousCB},'Units','Normalized','Position',[0.75 0.21 0.175 0.04]);
     obj.Handles.MemorizeSettingsButton = uicontrol('Style','pushbutton','String','Memorize settings','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.MemorizeSettingsCB},'Units','Normalized','Position',[0.75 0.17 0.175 0.04]);
     
     obj.Handles.SetDefaultPathButton = uicontrol('Style','pushbutton','String','Set start path','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.StartPathCB},'Units','Normalized','Position',[0.55 0.25  0.175 0.04],'HorizontalAlignment','left');
     obj.Handles.LoadFileButton = uicontrol('Style','pushbutton','String','Load new file','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.LoadFileCB},'Units','Normalized','Position',[0.55 0.21  0.175 0.04],'HorizontalAlignment','left','BackgroundColor',[0.9 0.7 0.7]);
     obj.Handles.AddToBatchButton = uicontrol('Style','pushbutton','String','Add current to batch','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.AddToBatchCB},'Units','Normalized','Position',[0.55 0.17  0.175 0.04],'HorizontalAlignment','left');
     obj.Handles.RemoveFromListButton = uicontrol('Style','pushbutton','String','Edit batch (See/remove)','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.EditBatchListCB},'Units','Normalized','Position',[0.55 0.13  0.175 0.04],'HorizontalAlignment','left');
     
     obj.Handles.ProcessButton = uicontrol('Style','pushbutton','String','Process batch !','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.ProcessCB},'Units','Normalized','Position',[0.55 0.07  0.175 0.04],'HorizontalAlignment','left');
     obj.Handles.CancelButton = uicontrol('Style','pushbutton','String','Cancel & exit','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
         'Callback',{@(~,~)obj.AbortCB},'Units','Normalized','Position',[0.75 0.02  0.175 0.04],'HorizontalAlignment','left');
     
     obj.DisableAll;

     end
end

methods(Hidden)
    
    function StartPathCB(obj)
        StartPath = uigetdir(obj.StartPath);
        if StartPath~=0,
            obj.StartPath = [StartPath filesep];
        end
    end
    
    function obj = LoadFileCB(obj)
        % Select a file
        [MovieFile,MoviePath] = uigetfile({[obj.StartPath '*.mj2;*.avi;*.mp4;*.m4v;*.mpg;*.mkv;*.wmv;*.mov']},'Please select a video file to process.');
        if MovieFile == 0
            if ~isempty(obj.CurrentFile)
                obj.EnableAll;
            end
            return
        end
        if ~isempty(obj.CurrentFile)
            obj.DisableAll;
        end
        FullMovieFile = fullfile(MoviePath,MovieFile);
        
        % Retrieve the basename, and assess whether we have one of our
        % thermal recordings (specific for our naming convention, but this
        % can be ignored for any different configuration and won't
        % influence the processing)
        if contains(FullMovieFile,'_IR.'),
            % Split the name to retrieve the basename
            Basename = strsplit(MovieFile,'_IR');
            Basename = Basename{1};
            VideoMode = 'Thermal';
        else
            [~,Basename] = fileparts(MovieFile);
            VideoMode = 'RGB';
        end

        % Check whether the movie was already tracked
        TrackingLogFile = [MoviePath Basename,'_Tracking.mat'];
        if exist(TrackingLogFile,'file') == 2,
            TrackingLog = load(TrackingLogFile);
            if isfield(TrackingLog,VideoMode),
                if isfield(TrackingLog.(VideoMode),'Center'),
                    if ~isempty(TrackingLog.(VideoMode).Center)
                        Answer = questdlg('This file was already processed, do you wish to continue anyway?','Please choose...','Yes (continue)','No (abort)','Yes (continue)');
                        if ~strcmpi(Answer,'Yes (continue)')
                            obj.EnableAll;
                            return
                        end
                    end
                end
            end
        end
        obj.Basename = Basename;

        % Reset background
        obj.Parameters.BackGround.Image = [];
        obj.Parameters.BackGround.PickedTimes = [];
        obj.Parameters.BackGround.Enable = 0;
        obj.Handles.BackGroundEnable.Enable = 'off';
        
        % Open file
        obj.Movie = VideoReader(FullMovieFile);
        
        % We have to check whether we have a greyscale movie
        FrameTest = obj.Movie.readFrame;
        if strcmpi(VideoMode, 'RGB'),
            if size(FrameTest,3) == 1,
                % We have a greyscale movie
                VideoMode = 'GreyScale';
            end
        else 
            % We could have an *_IR file but with 3 channels
            % (unlikely if properly preprocessed but just in case)
            if size(FrameTest,3)>1,
                Msg = ['This thermal movie is not Greyscale.' newline,...
                    'It is likely that the channel is repeated 3 times.' newline,...
                    'Channel 1 will be used.'];
               T = warndlg(Msg) ;
               waitfor(T)
               warning(Msg)
            end
        end
        obj.Parameters.VideoMode = VideoMode;
        
        % Reset player
        obj.FrameRate = obj.Movie.FrameRate;
        obj.SubSlider.XLim(2) = obj.Movie.Duration+0.5;
        obj.SliderLine.XData = [0 0];
        obj.CurrentFile = FullMovieFile;
        obj.TrackingLogFile = TrackingLogFile;
        obj.CurrentTime = 0;
        
        % Check frame properties and selection
        if strcmpi(obj.Parameters.VideoMode,'RGB'),
            obj.Handles.RelativeIntensityLow.Value = 1;
            obj.Handles.RelativeIntensityHigh.Value = 0;
            % Reset UI
            obj.Handles.RChannel.Value = 0;
            obj.Handles.GChannel.Value = 0;
            obj.Handles.BChannel.Value = 0;
            obj.Handles.GreyChannel.Value = 0;
            % Check which channel to use and apply to UI
            if strcmpi(obj.Parameters.Channel,'R'),
                obj.Handles.RChannel.Value = 1; % Just after initialization or reset
            elseif strcmpi(obj.Parameters.Channel,'G')
                obj.Handles.GChannel.Value = 1; % Just after initialization or reset
            elseif strcmpi(obj.Parameters.Channel,'B')
                obj.Handles.BChannel.Value = 1; % Just after initialization or reset
            elseif strcmpi(obj.Parameters.Channel,'Grey')
                obj.Handles.GreyChannel.Value = 1; % Just after initialization or reset
            else
                % If none selected
                obj.Parameters.Channel = 'R';
                obj.Handles.RChannel.Value = 1; % Just after initialization or reset
            end
        else
            obj.Handles.RChannel.Value = 0;
            obj.Handles.GChannel.Value = 0;
            obj.Handles.BChannel.Value = 0;
            obj.Handles.GreyChannel.Value = 1;
            obj.Parameters.MouseRelativeIntensity = 'High'; % By default for thermal, could be different for a "normal" grey movie, in which case it can still be changed via the UI
            obj.Handles.RelativeIntensityLow.Value = 0;
            obj.Handles.RelativeIntensityHigh.Value = 1;
        end

        obj.EnableAll;
        obj.ProcessFrame('Initialize');
        obj.SubMovie.CLim = [obj.Handles.LowCLimLine.XData(1) obj.Handles.HighCLimLine.XData(1)];
        drawnow
        
        if strcmpi(obj.Parameters.VideoMode,'RGB'),
            % Make sure channel selection UI is enabled
            obj.Handles.RChannel.Enable = 'on';
            obj.Handles.GChannel.Enable = 'on';
            obj.Handles.BChannel.Enable = 'on';
            obj.Handles.GreyChannel.Enable = 'on';
        else
            % Disable channel selection UI
            obj.Handles.RChannel.Enable = 'off';
            obj.Handles.GChannel.Enable = 'off';
            obj.Handles.BChannel.Enable = 'off';
            obj.Handles.GreyChannel.Enable = 'off';
        end
    end

    % Restore the parameters' values to the default values
    function obj = ResetDefaultCB(obj)
        for P = 1 : length(obj.Parameters.Names),
            obj.Parameters.(obj.Parameters.Names{P}) =  obj.DefaultParameters.(obj.Parameters.Names{P});
        end
        obj.ApplySettings;
    end
    
    % Keep the current parameters' values in memory
    function obj = MemorizeSettingsCB(obj)
        for P = 1 : length(obj.Parameters.Names),
            obj.LastParameters.(obj.Parameters.Names{P}) = obj.Parameters.(obj.Parameters.Names{P});
        end
    end
    
    % Restore the parameters' values to the last "saved"/used values
    function obj = ResetPreviousCB(obj)
        if ~isempty(obj.LastParameters)
            for P = 1 : length(obj.Parameters.Names),
                obj.Parameters.(obj.Parameters.Names{P}) =  obj.LastParameters.(obj.Parameters.Names{P});
            end
        end
        obj.ApplySettings;
    end
    
    % Change the UI to the current values
    function ApplySettings(obj)
        obj.Handles.Threshold.Line.XData  = [obj.Parameters.Threshold obj.Parameters.Threshold];
        obj.Handles.Threshold.Edit.String = num2str(obj.Parameters.Threshold);
        obj.Handles.RP.Line.XData  = [obj.Parameters.ReflectionPenalty obj.Parameters.ReflectionPenalty];
        obj.Handles.RP.Edit.String = num2str(obj.Parameters.ReflectionPenalty);
        obj.Handles.MC1Value.CheckBox.Value = obj.Parameters.MC1Enable;
        obj.Handles.MC1Value.Edit.String = num2str(obj.Parameters.MC1Value);
        obj.Handles.MC2Value.CheckBox.Value = obj.Parameters.MC2Enable;
        obj.Handles.MC2Value.Edit.String = num2str(obj.Parameters.MC2Value);
        obj.Handles.MO1Value.CheckBox.Value = obj.Parameters.MO1Enable;
        obj.Handles.MO1Value.Edit.String = num2str(obj.Parameters.MO1Value);
        obj.Handles.FilterSize.CheckBox.Value = obj.Parameters.FilterSizeEnable;
        obj.Handles.FilterSize.Edit.String = num2str(obj.Parameters.FilterSize);
        obj.Handles.SmoothContour.CheckBox.Value = obj.Parameters.SmoothContourEnable;
        obj.Handles.SmoothContour.Edit.String = num2str(obj.Parameters.SmoothContourValue);
    end
    
    % Track and display the results
    function varargout = ProcessFrame(obj,ModeProcessFrame)
        varargout = {};
        if strcmpi(ModeProcessFrame,'Slide'),
            SliderUpdate = false;
            ModeProcessFrame = 'Plot';
        else
            SliderUpdate = true;
        end
        
        if obj.Movie.hasFrame,
            obj.CurrentTime = obj.Movie.CurrentTime;
            Frame0 = obj.Movie.readFrame;
            
            % Check which channel to use and retrieve frame
            if strcmpi(obj.Parameters.VideoMode,'RGB'),
                if strcmpi(obj.Parameters.Channel,'R'),
                    ChanNum = 1;
                elseif strcmpi(obj.Parameters.Channel,'G')
                    ChanNum = 2;
                elseif strcmpi(obj.Parameters.Channel,'B')
                    ChanNum = 3;
                elseif strcmpi(obj.Parameters.Channel,'Grey')
                    ChanNum = 1:size(Frame0,3);
                end
            else
                ChanNum = 1;
            end
            FrameF = Frame0(:,:,ChanNum);
                
            % Remove background if needed
            if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                if obj.Parameters.BackGround.Enable & ~isempty(obj.Parameters.BackGround.Image)
                    if size(obj.Parameters.BackGround.Image,3) == 1,
                        FrameDeBack = 255-uint8(255+double(FrameF)- double(obj.Parameters.BackGround.Image));
                    else
                        FrameDeBack = 255-uint8(255+double(FrameF)- double(obj.Parameters.BackGround.Image(:,:,ChanNum)));
                    end
                else
                    FrameDeBack = 255-uint8(FrameF);
                end
            else
                if obj.Parameters.BackGround.Enable & ~isempty(obj.Parameters.BackGround.Image)
                    if size(obj.Parameters.BackGround.Image,3) == 1,
                        FrameDeBack = uint8(double(FrameF)- double(obj.Parameters.BackGround.Image));
                    else
                        FrameDeBack = uint8(double(FrameF)- double(obj.Parameters.BackGround.Image(:,:,ChanNum)));
                    end
                else
                    FrameDeBack = uint8(FrameF);
                end
            end
            if strcmpi(obj.Parameters.Channel,'Grey') && strcmpi(obj.Parameters.VideoMode,'RGB')
                FrameF = rgb2gray(FrameF);
                FrameDeBack = rgb2gray(FrameDeBack);
            end
            
            % Apply reflection penalty if needed
            if obj.Parameters.ReflectionPenalty>1 && ~isempty(obj.Parameters.Mask)
                    FrameDeBack(obj.Parameters.OutsideMask) = FrameDeBack(obj.Parameters.OutsideMask)/obj.Parameters.ReflectionPenalty;
            end
            
            % Threshold
            FrameDeBack_BW = FrameDeBack>obj.Parameters.Threshold;
            
            % Size filtering if enabled (not directly in the GUI)
            if obj.Parameters.FilterSizeEnable,
                FrameDeBack_BW = bwareaopen(FrameDeBack_BW,10);
            end
            if obj.Parameters.MO1Enable
                FrameDeBack_BW = imopen(FrameDeBack_BW,obj.Parameters.StructuringElement.MO1i);
            end
            if obj.Parameters.FilterSizeEnable,
                FrameDeBack_BW = bwareaopen(FrameDeBack_BW,10);
            end
            
            RemoveMask = true(size(FrameDeBack));
            FalseMask = false(size(FrameDeBack));
            if obj.Parameters.ReflectionPenalty>1 && ~isempty(obj.Parameters.Mask)
                % Remove non-crossing residuals outside the boundaries
                FrameDeBack_BWBU = FrameDeBack_BW;
                OriginalChunks = regionprops(FrameDeBack_BW,'PixelIdxList');
                for ChunkNumber = 1 : numel(OriginalChunks),
                    MaskC = FalseMask;
                    MaskC(OriginalChunks(ChunkNumber).PixelIdxList) = true;
                    if any(obj.Parameters.Mask & MaskC,'all'),
                        RemoveMask(MaskC) = false;
                    end
                end
                FrameDeBack_BW(RemoveMask) = false;
                if ~any(FrameDeBack_BW),
                    FrameDeBack_BW = FrameDeBack_BWBU;
                end
            end
            if  obj.Parameters.MC1Enable,
                FrameDeBack_BW = imclose(FrameDeBack_BW,obj.Parameters.StructuringElement.MC1);
            end
            if obj.Parameters.FilterSizeEnable,
                FrameDeBack_BW = bwareaopen(FrameDeBack_BW,obj.Parameters.FilterSize);
            end
            if  obj.Parameters.MC2Enable,
                FrameDeBack_BW = imclose(FrameDeBack_BW,obj.Parameters.StructuringElement.MC2);
            end
            if obj.Parameters.MO1Enable
                FrameDeBack_BW = imopen(FrameDeBack_BW,obj.Parameters.StructuringElement.MO1);
            end
            
            % Pick the biggest remaining object
            closeBW = bwareafilt(FrameDeBack_BW,1);
            
            % Get contour
            if any(closeBW,'all') && ~all(closeBW,'all'),
                CC = contourc(double(closeBW),1);
                IndexCut = [find(CC(1,:) == CC(1,1)),numel(CC(1,:))+1 ];
                if numel(IndexCut)>1,
                    Chunks = diff(IndexCut);
                    [~,MaxIndx] = max(Chunks);
                    CC = CC(:,IndexCut(MaxIndx)+1:IndexCut(MaxIndx+1)-1);
                else
                    CC = CC(:,2:end);
                end
                if obj.Parameters.SmoothContourEnable,
                    CC(1,:) = smoothdata(CC(1,:),'gaussian',obj.Parameters.SmoothContourValue);
                    CC(2,:) = smoothdata(CC(2,:),'gaussian',obj.Parameters.SmoothContourValue);
                end
                % Repeat value to make sure it is closed
                CC = [CC,CC(:,1)];
                % Get center of gravity
                Meas = regionprops(closeBW,'Centroid');
                Center_G = Meas(1).Centroid;
            else
                closeBW = NaN;
                CC = [NaN;NaN];
                Center_G = [NaN NaN];
            end
            
            if strcmpi(ModeProcessFrame,'Process')
                varargout = {closeBW,CC};
            end
            
            
            % Plotting - this section could be condensed to group similar
            % cases, but then become hard to follow: the choice was made
            % to treat the cases one by one to make it clear, at the
            % cost of a few more lines of code and redundancy
            
            if strcmpi(ModeProcessFrame,'Plot')
                % RGB movie
                if strcmpi(obj.Parameters.VideoMode,'RGB'),
                    if obj.Handles.OriginalButton.Value == 1
                        % Original colormode: RGB image
                        if strcmpi(obj.CurrentImageMode,'Greyscale')
                            % We need to replace the image
                            delete(obj.FramePlot)
                            obj.CurrentImageMode = 'RGB';
                            if (obj.Parameters.BackGround.SubstractMain & ~isempty(obj.Parameters.BackGround.Image)),
                                % Background substracted for display
                                obj.FramePlot = image(uint8(255+double(Frame0) - double(obj.Parameters.BackGround.Image)),'Parent',obj.SubMovie);
                            else
                                % Raw frame
                                obj.FramePlot = image(Frame0,'Parent',obj.SubMovie);
                            end
                        else
                            if (obj.Parameters.BackGround.SubstractMain & ~isempty(obj.Parameters.BackGround.Image)),
                                % Background substracted for display
                                obj.FramePlot.CData = uint8(255+double(Frame0) - double(obj.Parameters.BackGround.Image));
                            else
                                % Raw frame
                                obj.FramePlot.CData = Frame0;
                            end
                        end
                    else
                        % Single channel: channel selected for tracking
                        if ~strcmpi(obj.CurrentImageMode,'Greyscale')
                            % We need to replace the image
                            delete(obj.FramePlot)
                            obj.CurrentImageMode = 'Greyscale';
                            if (obj.Parameters.BackGround.SubstractMain & ~isempty(obj.Parameters.BackGround.Image)),
                                obj.FramePlot = imagesc(FrameDeBack,'Parent',obj.SubMovie);
                            else
                                % Raw frame (single channel)
                                obj.FramePlot = imagesc(FrameF,'Parent',obj.SubMovie);
                            end
                            % Set the right colormap
                            if obj.Handles.JetButton.Value
                                obj.SubMovie.Colormap = jet;
                            elseif obj.Handles.ParulaButton.Value
                                obj.SubMovie.Colormap = parula;
                            elseif obj.Handles.HotWhiteButton.Value
                                obj.SubMovie.Colormap = obj.Parameters.HotWhite;
                            end
                        else
                            if (obj.Parameters.BackGround.SubstractMain & ~isempty(obj.Parameters.BackGround.Image)),
                                obj.FramePlot.CData = FrameDeBack;
                            else
                                % Raw frame (single channel)
                                obj.FramePlot.CData = FrameF;
                            end
                        end
                    end
                else
                    % Thermal or other greyscale movie
                    if ~strcmpi(obj.CurrentImageMode,'Greyscale')
                        % We need to replace the image
                        delete(obj.FramePlot)
                        obj.CurrentImageMode = 'Greyscale';
                        if (obj.Parameters.BackGround.SubstractMain & ~isempty(obj.Parameters.BackGround.Image)),
                            obj.FramePlot = imagesc(FrameDeBack,'Parent',obj.SubMovie);
                        else
                            % Raw frame (single channel)
                            obj.FramePlot = imagesc(FrameF,'Parent',obj.SubMovie);
                        end
                        % Set the right colormap
                        if obj.Handles.OriginalButton.Value == 1
                            % Neutral colormap (bone)
                            obj.SubMovie.Colormap = bone;
                        elseif obj.Handles.JetButton.Value
                            obj.SubMovie.Colormap = jet;
                        elseif obj.Handles.ParulaButton.Value
                            obj.SubMovie.Colormap = parula;
                        elseif obj.Handles.HotWhiteButton.Value
                            obj.SubMovie.Colormap = obj.Parameters.HotWhite;
                        end
                    else
                        if (obj.Parameters.BackGround.SubstractMain & ~isempty(obj.Parameters.BackGround.Image)),
                            obj.FramePlot.CData = FrameDeBack;
                        else
                            % Raw frame (single channel)
                            obj.FramePlot.CData = FrameF;
                        end
                    end
                    obj.CurrentImageMode = 'Greyscale';
                end
                obj.SubMovie.XColor = 'none';
                obj.SubMovie.YColor = 'none';
            elseif strcmpi(ModeProcessFrame,'Initialize')
                % Set mode (changed if needed)
                obj.CurrentImageMode = 'RGB';
                
                hold(obj.SubMovie,'off')
                % RGB movie
                if strcmpi(obj.Parameters.VideoMode,'RGB'),
                    if obj.Handles.OriginalButton.Value == 1
                        % Original colormode: RGB image
                        if (obj.Parameters.BackGround.SubstractMain & ~isempty(obj.Parameters.BackGround.Image)),
                            % Background substracted for display
                            obj.FramePlot = image(uint8(255+double(Frame0) - double(obj.Parameters.BackGround.Image)),'Parent',obj.SubMovie);
                        else
                            % Raw frame
                            obj.FramePlot = image(Frame0,'Parent',obj.SubMovie);
                        end
                    else
                        % Single channel: channel selected for tracking
                        if (obj.Parameters.BackGround.SubstractMain & ~isempty(obj.Parameters.BackGround.Image)),
                            obj.FramePlot = imagesc(FrameDeBack,'Parent',obj.SubMovie);
                        else
                            % Raw frame (single channel)
                            obj.FramePlot = imagesc(FrameF,'Parent',obj.SubMovie);
                        end
                        % Set the right colormap
                        if obj.Handles.JetButton.Value
                            obj.SubMovie.Colormap = jet;
                        elseif obj.Handles.ParulaButton.Value
                            obj.SubMovie.Colormap = parula;
                        elseif obj.Handles.HotWhiteButton.Value
                            obj.SubMovie.Colormap = obj.Parameters.HotWhite;
                        end
                    end
                    obj.CurrentImageMode = 'Greyscale';
                else
                    % Thermal or other greyscale movie
                    if (obj.Parameters.BackGround.SubstractMain & ~isempty(obj.Parameters.BackGround.Image)),
                        obj.FramePlot = imagesc(FrameDeBack,'Parent',obj.SubMovie);
                    else
                        % Raw frame (single channel)
                        obj.FramePlot = imagesc(FrameF,'Parent',obj.SubMovie);
                    end
                    % Set the right colormap
                    if obj.Handles.OriginalButton.Value == 1
                        % Neutral colormap (bone)
                        obj.SubMovie.Colormap = bone;
                    elseif obj.Handles.JetButton.Value
                        obj.SubMovie.Colormap = jet;
                    elseif obj.Handles.ParulaButton.Value
                        obj.SubMovie.Colormap = parula;
                    elseif obj.Handles.HotWhiteButton.Value
                        obj.SubMovie.Colormap = obj.Parameters.HotWhite;
                    end
                    obj.CurrentImageMode = 'Greyscale';
                end
                obj.SubMovie.XColor = 'none';
                obj.SubMovie.YColor = 'none';
            end
            
            if ~strcmpi(ModeProcessFrame,'Initialize')
                obj.SpeedText.String = ['x' num2str(obj.Speed)];
                obj.ContourPlot.XData = CC(1,:);
                obj.ContourPlot.YData = CC(2,:);
                obj.CenterPlot.XData = Center_G(1);
                obj.CenterPlot.YData = Center_G(2);
                uistack(obj.FramePlot,'bottom')
            else
                hold(obj.SubMovie,'on')
                obj.SpeedText = text(0,0,'x1','FontSize',obj.FontScaling*22,'FontName','Arial','FontWeight','bold','Color','g','Parent',obj.SubMovie);
                obj.SpeedText.Position(1) = 0.85*obj.Movie.Width;
                obj.SpeedText.Position(2) = 0.95*obj.Movie.Height;
                obj.SpeedText.String = ['x' num2str(obj.Speed)];
                obj.ContourPlot = plot(CC(1,:),CC(2,:),'g','LineWidth',2,'Parent',obj.SubMovie);
                obj.CenterPlot = plot(Center_G(1),Center_G(2),'r+','LineWidth',2,'Parent',obj.SubMovie);
                if ~isempty(obj.Parameters.Shape)
                    if strcmpi(obj.Parameters.Shape.Type,'Circle'),
                        obj.Handles.Shape = drawcircle('Center',obj.Parameters.Shape.Center,'Radius',obj.Parameters.Shape.Radius,'Parent',obj.SubMovie);
                    else
                        obj.Handles.Shape = drawpolygon('Position',obj.Parameters.Shape.Vertices,'Parent',obj.SubMovie);
                    end
                    addlistener(obj.Handles.Shape,'MovingROI',@(~,~)obj.ReshapeROI);
                end
                drawnow
            end
            if SliderUpdate,
                obj.SliderLine.XData = [obj.CurrentTime obj.CurrentTime];
            end
        end
    end
    
    function SetPlay(obj)
       obj.Play = true;
       tic
       obj.ProcessFrame('Plot');
       while obj.Play
           TocT = toc;
           tic
           if obj.Movie.CurrentTime + TocT * obj.Speed<obj.Movie.Duration,
               obj.Movie.CurrentTime = obj.Movie.CurrentTime + TocT * obj.Speed;
               obj.ProcessFrame('Plot');
           else
               return
           end
       end
    end

    
    function PauseMovie(obj)
        obj.Play = false;
    end
    
    function DecreaseFrameRate(obj)
        obj.Speed = obj.Speed/2;
        obj.SpeedText.String = ['x' num2str(obj.Speed)];
        drawnow
    end
    
    function IncreaseFrameRate(obj)
        obj.Speed = obj.Speed*2;
        obj.SpeedText.String = ['x' num2str(obj.Speed)];
        drawnow
    end
    
    function Slide(obj)
        if ~isempty(obj.Movie),
            if ~obj.Dragging,
                obj.PrePlayState = obj.Play;
                obj.Play = false;
                obj.Dragging = true;
                obj.Figure.WindowButtonMotionFcn = @(~,~)obj.MovingTimeLine;
                obj.Figure.WindowButtonUpFcn = @(~,~)obj.Slide;
            else
                obj.Dragging = false;
                obj.Figure.WindowButtonMotionFcn = [];
                obj.Figure.WindowButtonUpFcn = [];
                if obj.PrePlayState
                    obj.SetPlay;
                end
            end
        end
    end
    
    function MovingTimeLine(obj)
        CurrentCursor = obj.SubMovie.CurrentPoint(1);
        TempNewTime = CurrentCursor/obj.SubMovie.XLim(2) * obj.Movie.Duration;
        if TempNewTime>0 && TempNewTime<=obj.Movie.Duration,
            obj.SliderLine.XData = [TempNewTime TempNewTime];
            drawnow
        else
            return
        end
        if ~obj.Refractory,
            obj.Refractory = true;
            obj.Movie.CurrentTime = TempNewTime;
            obj.ProcessFrame('Slide');
            drawnow
            obj.Refractory = false;
        end
    end


    function UpdateFrame(obj)
        % The refractory toggle switch is here to prevent an event to 
        % retrigger the update while it's already being processed; this
        % otherwise prevents keeping the same frame and just updating with
        % the changed parameters
        if ~obj.Refractory,
            obj.Refractory = true;
            obj.Movie.CurrentTime = obj.CurrentTime;
            obj.ProcessFrame('Plot');
            obj.Refractory = false;
        end
    end
    
    function SlideLowCLim(obj)
        if ~obj.Dragging,
            obj.Dragging = true;
            obj.Figure.WindowButtonMotionFcn = @(~,~)obj.MovingLowCLim;
            obj.Figure.WindowButtonUpFcn = @(~,~)obj.SlideLowCLim;
        else
            obj.Dragging = false;
            obj.Figure.WindowButtonMotionFcn = [];
            obj.Figure.WindowButtonUpFcn = [];
        end
    end
    
    function MovingLowCLim(obj)
        CurrentCursor = round(obj.Handles.SubCLim.CurrentPoint(1));
        if CurrentCursor>=0 && CurrentCursor<=255 && obj.SubMovie.CLim(2)>CurrentCursor
            obj.Handles.LowCLimEdit.String = CurrentCursor;
            obj.SubMovie.CLim(1) = CurrentCursor;
            obj.Handles.LowCLimLine.XData = [CurrentCursor CurrentCursor];
            drawnow
        elseif CurrentCursor<0,
            obj.Handles.LowCLimEdit.String = '0';
            obj.SubMovie.CLim(1) = 0;
            obj.Handles.LowCLimLine.XData = [0 0];
            drawnow
        end
    end
    
    
    function SlideHighCLim(obj)
        if ~obj.Dragging,
            obj.Dragging = true;
            obj.Figure.WindowButtonMotionFcn = @(~,~)obj.MovingHighCLim;
            obj.Figure.WindowButtonUpFcn = @(~,~)obj.SlideHighCLim;
        else
            obj.Dragging = false;
            obj.Figure.WindowButtonMotionFcn = [];
            obj.Figure.WindowButtonUpFcn = [];
        end
    end
    
    function MovingHighCLim(obj)
        CurrentCursor = round(obj.Handles.SubCLim.CurrentPoint(1));
        if CurrentCursor>=0 && CurrentCursor<=255 && obj.SubMovie.CLim(1)<CurrentCursor,
            obj.Handles.HighCLimEdit.String = CurrentCursor;
            obj.SubMovie.CLim(2) = CurrentCursor;
            obj.Handles.HighCLimLine.XData = [CurrentCursor CurrentCursor];
            drawnow
        elseif CurrentCursor>255,
            obj.Handles.HighCLimEdit.String = '255';
            obj.SubMovie.CLim(2) = 255;
            obj.Handles.HighCLimLine.XData = [255 255];
            drawnow
        end
    end
    
  
    function LowCLimEditCB(obj)
          if rem(str2double(obj.Handles.LowCLimEdit.String),1) == 0 && str2double(obj.Handles.LowCLimEdit.String)>=0 && str2double(obj.Handles.LowCLimEdit.String)<=255 && str2double(obj.Handles.LowCLimEdit.String)<str2double(obj.Handles.HighCLimEdit.String)
              obj.Handles.LowCLimLine.XData = [str2double(obj.Handles.LowCLimEdit.String) str2double(obj.Handles.LowCLimEdit.String)];
              obj.SubMovie.CLim(1) = str2double(obj.Handles.LowCLimEdit.String);
          else
              obj.Handles.LowCLimEdit.String = num2str(obj.Handles.LowCLimLine.XData(1));
          end
    end
    
    function HighCLimEditCB(obj)
        if rem(str2double(obj.Handles.HighCLimEdit.String),1) == 0 && str2double(obj.Handles.HighCLimEdit.String)>=0 && str2double(obj.Handles.HighCLimEdit.String)<=255 && str2double(obj.Handles.LowCLimEdit.String)<str2double(obj.Handles.HighCLimEdit.String)
            obj.Handles.HighCLimLine.XData = [str2double(obj.Handles.HighCLimEdit.String) str2double(obj.Handles.HighCLimEdit.String)];
            obj.SubMovie.CLim(2) = str2double(obj.Handles.HighCLimEdit.String);
        else
            obj.Handles.HighCLimEdit.String = num2str(obj.Handles.HighCLimLine.XData(1));
        end
    end
    
    function SetCLimCB(obj)
        if str2double(obj.Handles.LowCLimEdit.String)>=0 && str2double(obj.Handles.LowCLimEdit.String)<=255
            obj.Handles.LowCLimLine.XData = [str2double(obj.Handles.LowCLimEdit.String) str2double(obj.Handles.LowCLimEdit.String)];
            obj.SubMovie.CLim(1) = str2double(obj.Handles.LowCLimEdit.String);
        end
        if str2double(obj.Handles.HighCLimEdit.String)>=0 && str2double(obj.Handles.HighCLimEdit.String)<=255
            obj.Handles.HighCLimLine.XData = [str2double(obj.Handles.HighCLimEdit.String) str2double(obj.Handles.HighCLimEdit.String)];
            obj.SubMovie.CLim(2) = str2double(obj.Handles.HighCLimEdit.String);
        end
    end
    
    function ResetCLimCB(obj)
        obj.Handles.LowCLimEdit.String = '0';
        obj.Handles.HighCLimEdit.String = '255';
        obj.SetCLimCB;
    end
    
    function JetCB(obj)
        if obj.Handles.JetButton.Value == 1,
            obj.Handles.ParulaButton.Value = 0;
            obj.Handles.HotWhiteButton.Value = 0;
            obj.Handles.OriginalButton.Value = 0;
            obj.SubMovie.Colormap = jet;
        elseif obj.Handles.JetButton.Value == 0 && obj.Handles.OriginalButton.Value == 0 &&  obj.Handles.HotWhiteButton.Value == 0,
            obj.Handles.JetCB.Value = 1;
        end
        if obj.Play,
            obj.Play = false;
            obj.ProcessFrame('Plot');
            obj.SetPlay;
        else
            obj.Movie.CurrentTime = obj.CurrentTime;
            obj.ProcessFrame('Plot');
        end
    end
    
    function ParulaCB(obj)
        if obj.Handles.ParulaButton.Value == 1,
            obj.Handles.JetButton.Value = 0;
            obj.Handles.HotWhiteButton.Value = 0;
            obj.Handles.OriginalButton.Value = 0;
            obj.SubMovie.Colormap = parula;
        elseif obj.Handles.JetButton.Value == 0 && obj.Handles.ParulaButton.Value == 0 &&  obj.Handles.HotWhiteButton.Value == 0,
            obj.Handles.ParulaButton.Value = 1;
        end
        obj.Movie.CurrentTime = obj.CurrentTime;
        if obj.Play,
            obj.Play = false;
            obj.ProcessFrame('Plot');
            obj.SetPlay;
        else
            obj.Movie.CurrentTime = obj.CurrentTime;
            obj.ProcessFrame('Plot');
        end
    end
    
    function HWCB(obj)
        if obj.Handles.HotWhiteButton.Value == 1,
            obj.Handles.JetButton.Value = 0;
            obj.Handles.ParulaButton.Value = 0;
            obj.Handles.OriginalButton.Value = 0;
            obj.SubMovie.Colormap = obj.Parameters.HotWhite;
        elseif obj.Handles.JetButton.Value == 0 && obj.Handles.ParulaButton.Value == 0 &&  obj.Handles.OriginalButton.Value == 0,
            obj.Handles.HotWhiteButton.Value = 1;
        end
        if obj.Play,
            obj.Play = false;
            obj.ProcessFrame('Plot');
            obj.SetPlay;
        else
            obj.Movie.CurrentTime = obj.CurrentTime;
            obj.ProcessFrame('Plot');
        end
    end
    
    function OriginalCB(obj)
        if obj.Handles.OriginalButton.Value == 1,
            obj.Handles.JetButton.Value = 0;
            obj.Handles.ParulaButton.Value = 0;
            obj.Handles.HotWhiteButton.Value = 0;
            if ~strcmpi(obj.Parameters.VideoMode,'RGB'),
                obj.SubMovie.Colormap = bone; % For rgb, normal image instead
            end
        elseif obj.Handles.JetButton.Value == 0 && obj.Handles.ParulaButton.Value == 0 &&  obj.Handles.HotWhiteButton.Value == 0,
            obj.Handles.OriginalButton.Value = 1;
        end
        if obj.Play,
            obj.Play = false;
            obj.ProcessFrame('Plot');
            obj.SetPlay;
        else
            obj.Movie.CurrentTime = obj.CurrentTime;
            obj.ProcessFrame('Plot');
        end
    end
    
    function RChannelCB(obj)
        if obj.Handles.RChannel.Value,
            if obj.Play
                obj.Play = false;
                RePlay = true;
            else
                RePlay = false;
            end
            obj.Handles.GChannel.Value = 0;
            obj.Handles.BChannel.Value = 0;
            obj.Handles.GreyChannel.Value = 0;
            obj.Parameters.Channel = 'R';
            drawnow
            if RePlay,
                obj.ProcessFrame('Plot');
                obj.SetPlay;
            else
                obj.Movie.CurrentTime = obj.CurrentTime;
                obj.ProcessFrame('Plot');
            end
        elseif  obj.Handles.GChannel.Value == 0 && obj.Handles.BChannel.Value == 0 && obj.Handles.GreyChannel.Value == 0,
            obj.Handles.RChannel.Value = 1;
        end
    end
    
    function GChannelCB(obj)
        if obj.Handles.GChannel.Value,
            if obj.Play
                obj.Play = false;
                RePlay = true;
            else
                RePlay = false;
            end
            obj.Handles.RChannel.Value = 0;
            obj.Handles.BChannel.Value = 0;
            obj.Handles.GreyChannel.Value = 0;
            obj.Parameters.Channel = 'G';
            drawnow
            if RePlay,
                obj.ProcessFrame('Plot');
                obj.SetPlay;
            else
                obj.Movie.CurrentTime = obj.CurrentTime;
                obj.ProcessFrame('Plot');
            end
        elseif  obj.Handles.RChannel.Value == 0 && obj.Handles.BChannel.Value == 0 && obj.Handles.GreyChannel.Value == 0,
            obj.Handles.GChannel.Value = 1;
        end
    end
    
    function BChannelCB(obj)
        if obj.Handles.BChannel.Value,
            if obj.Play
                obj.Play = false;
                RePlay = true;
            else
                RePlay = false;
            end
            obj.Handles.RChannel.Value = 0;
            obj.Handles.GChannel.Value = 0;
            obj.Handles.GreyChannel.Value = 0;
            obj.Parameters.Channel = 'B';
            drawnow
            if RePlay,
                obj.ProcessFrame('Plot');
                obj.SetPlay;
            else
                obj.Movie.CurrentTime = obj.CurrentTime;
                obj.ProcessFrame('Plot');
            end
        elseif  obj.Handles.RChannel.Value == 0 && obj.Handles.GChannel.Value == 0 && obj.Handles.GreyChannel.Value == 0,
            obj.Handles.BChannel.Value = 1;
        end
    end
     function GreyChannelCB(obj)
        if obj.Handles.GreyChannel.Value,
            if obj.Play
                obj.Play = false;
                RePlay = true;
            else
                RePlay = false;
            end
            obj.Handles.RChannel.Value = 0;
            obj.Handles.GChannel.Value = 0;
            obj.Handles.BChannel.Value = 0;
            obj.Parameters.Channel = 'Grey';
            drawnow
            if RePlay,
                obj.ProcessFrame('Plot');
                obj.SetPlay;
            else
                obj.Movie.CurrentTime = obj.CurrentTime;
                obj.ProcessFrame('Plot');
            end
        elseif  obj.Handles.RChannel.Value == 0 && obj.Handles.BChannel.Value == 0 && obj.Handles.GChannel.Value == 0,
            obj.Handles.GreyChannel.Value = 1;
        end
     end
     
     function RelativeIntensityHighCB(obj)
         if  obj.Handles.RelativeIntensityHigh.Value,
             obj.Handles.RelativeIntensityLow.Value = 0;
             obj.Parameters.MouseRelativeIntensity = 'High';
         else
             obj.Handles.RelativeIntensityLow.Value = 1;
             obj.Parameters.MouseRelativeIntensity = 'Low';
         end
         if ~obj.Play,
             obj.UpdateFrame;
         end
     end
     
     function RelativeIntensityLowCB(obj)
         if  obj.Handles.RelativeIntensityLow.Value,
             obj.Handles.RelativeIntensityHigh.Value = 0;
             obj.Parameters.MouseRelativeIntensity = 'Low';
         else
             obj.Handles.RelativeIntensityHigh.Value = 1;
             obj.Parameters.MouseRelativeIntensity = 'High';
         end
         if ~obj.Play,
             obj.UpdateFrame;
         end
     end
     
     function SliderThresholdCB(obj)
         if ~obj.Dragging,
            obj.Dragging = true;
            obj.Figure.WindowButtonMotionFcn = @(~,~)obj.MovingThreshold;
            obj.Figure.WindowButtonUpFcn = @(~,~)obj.SliderThresholdCB;
        else
            obj.Dragging = false;
            obj.Figure.WindowButtonMotionFcn = [];
            obj.Figure.WindowButtonUpFcn = [];
        end
    end
    
    function MovingThreshold(obj)
        CurrentCursor = obj.Handles.SubThreshold.CurrentPoint(1);
        if CurrentCursor>=0 && CurrentCursor<=255,
            obj.Parameters.Threshold = CurrentCursor;
            obj.Handles.Threshold.Edit.String = num2str(CurrentCursor);
            obj.Handles.Threshold.Line.XData = [CurrentCursor CurrentCursor];
        elseif CurrentCursor>255,
            obj.Handles.Threshold.Edit.String = '255';
            obj.Parameters.Threshold = 255;
            obj.Handles.Threshold.Line.XData = [255 255];
        elseif CurrentCursor<0,
            obj.Handles.Threshold.Edit.String = '0';
            obj.Parameters.Threshold = 0;
            obj.Handles.Threshold.Line.XData = [0 0];
        end
        drawnow
        if ~obj.Play,
            obj.UpdateFrame;
        end
    end
    
     function ThresholdEditCB(obj)
         if str2double(obj.Handles.Threshold.Edit.String)>=0 && str2double(obj.Handles.Threshold.Edit.String)<=255,
             obj.Parameters.Threshold = str2double(obj.Handles.Threshold.Edit.String);
             obj.Handles.Threshold.Line.XData =  [str2double(obj.Handles.Threshold.Edit.String) str2double(obj.Handles.Threshold.Edit.String)];
         else
             obj.Handles.Threshold.Edit.Value = num2str(obj.Handles.Threshold.Slider.Value);
         end
     end
        
     function SliderRPCB(obj)
       if ~obj.Dragging,
            obj.Dragging = true;
            obj.Figure.WindowButtonMotionFcn = @(~,~)obj.MovingRP;
            obj.Figure.WindowButtonUpFcn = @(~,~)obj.SliderRPCB;
        else
            obj.Dragging = false;
            obj.Figure.WindowButtonMotionFcn = [];
            obj.Figure.WindowButtonUpFcn = [];
        end
    end
    
    function MovingRP(obj)
        CurrentCursor = obj.Handles.SubRP.CurrentPoint(1);
        if CurrentCursor>=1 && CurrentCursor<=10,
            obj.Parameters.ReflectionPenalty = CurrentCursor;
            obj.Handles.RP.Edit.String = num2str(CurrentCursor);
            obj.Handles.RP.Line.XData = [CurrentCursor CurrentCursor];
            drawnow
            if ~obj.Play,
                obj.UpdateFrame;
            end
        elseif CurrentCursor>10,
            obj.Parameters.ReflectionPenalty = 10;
            obj.Handles.RP.Edit.String = '10';
            obj.Handles.RP.Line.XData = [10 10];
            drawnow
            if ~obj.Play,
                obj.UpdateFrame;
            end
        elseif CurrentCursor<1,
            obj.Handles.RP.Edit.String = '1';
            obj.Parameters.ReflectionPenalty = 1;
            obj.Handles.RP.Line.XData = [1 1];
            drawnow
            if ~obj.Play,
                obj.UpdateFrame;
            end
        end
    end
    
     
     function RPEditCB(obj)
         if str2double(obj.Handles.RP.Edit.String)>=1 && str2double(obj.Handles.RP.Edit.String)<=10,
             obj.Parameters.ReflectionPenalty = str2double(obj.Handles.RP.Edit.String);
             obj.Handles.RP.Line.XData =  [str2double(obj.Handles.RP.Edit.String) str2double(obj.Handles.RP.Edit.String)];
         else
             obj.Handles.RP.Edit.Value = num2str(obj.Handles.RP.Slider.Value);
         end
     end
     
     function CircleButtonCB(obj)
             obj.Handles.Shape = drawcircle(obj.SubMovie);
             obj.Parameters.Mask = obj.Handles.Shape.createMask(obj.Movie.Height,obj.Movie.Width);
             OutMask = true(obj.Movie.Height,obj.Movie.Width);
             OutMask(obj.Parameters.Mask) = false;
             obj.Parameters.OutsideMask = OutMask;
             obj.Parameters.Shape.Type = 'Circle';
             obj.Parameters.Shape.Center = obj.Handles.Shape.Center;
             obj.Parameters.Shape.Radius = obj.Handles.Shape.Radius;
             addlistener(obj.Handles.Shape,'MovingROI',@(~,~)obj.ReshapeROI);
             obj.Handles.RP.Edit.String = num2str(1.5);
             obj.RPEditCB;
             if ~obj.Play,
                 obj.UpdateFrame;
             end
     end
     
     function ReshapeROI(obj)
         obj.Parameters.Mask = obj.Handles.Shape.createMask(obj.Movie.Height,obj.Movie.Width);
         OutMask = true(obj.Movie.Height,obj.Movie.Width);
         OutMask(obj.Parameters.Mask) = false;
         obj.Parameters.OutsideMask = OutMask;
         if strcmpi(obj.Parameters.Shape.Type,'Circle'),
             obj.Parameters.Shape.Center = obj.Handles.Shape.Center;
             obj.Parameters.Shape.Radius = obj.Handles.Shape.Radius;
         else
             obj.Parameters.Shape.Vertices = obj.Handles.Shape.Position;
         end
         if ~obj.Play,
             obj.UpdateFrame;
         end
     end
     
     function FreeButtonCB(obj)
         obj.Handles.Shape = drawpolygon(obj.SubMovie);
         obj.Parameters.Mask = obj.Handles.Shape.createMask(obj.Movie.Height,obj.Movie.Width);
         OutMask = true(obj.Movie.Height,obj.Movie.Width);
         OutMask(obj.Parameters.Mask) = false;
         obj.Parameters.OutsideMask = OutMask;
         obj.Parameters.Shape.Type = 'Polygon';
         obj.Parameters.Shape.Vertices = obj.Handles.Shape.Position;
         addlistener(obj.Handles.Shape,'MovingROI',@(~,~)obj.ReshapeROI);
         obj.Handles.RP.Edit.String = num2str(1.5);
         obj.RPEditCB;
         if ~obj.Play,
             obj.UpdateFrame;
         end
     end
     
     function DeleteButtonCB(obj)
         delete(obj.Handles.Shape);
         obj.Handles.Shape = [];
         obj.Parameters.Shape = [];
         obj.Parameters.Mask = [];
         obj.Parameters.OutsideMask = [];
     end    
     
     function DrawCalibrationCB(obj)
         CalibrationLine = drawline(obj.SubMovie);
         obj.Parameters.Calibration.Line = CalibrationLine.Position;
         delete(CalibrationLine);         
     end
     
     function EditCalibrationCB(obj)
         TempInput = str2double(obj.Handles.CalibrationEdit.String);
         if ~isempty(TempInput) && ~isnan(TempInput) && numel(TempInput)==1 && TempInput>=0,
             obj.Parameters.Calibration.Length = TempInput;
         else
             obj.Handles.CalibrationEdit.String = num2str(obj.Parameters.Calibration.Length);
         end
     end   
     
    
     function MC1CB(obj)
         if obj.Handles.MC1Value.CheckBox.Value == 1,
             obj.Parameters.MC1Enable = true;
         else
             obj.Parameters.MC1Enable = false;
         end
         if ~obj.Play,
             obj.UpdateFrame;
         end
     end
     
     function MC1EditCB(obj)
         Temp = str2double(obj.Handles.MC1Value.Edit.String);
         if Temp>=1 && rem(Temp,1) == 0,
             obj.Parameters.MC1Value = Temp;
             obj.DefaultParameters.StructuringElement.MC1 = strel('disk',Temp);
             if ~obj.Handles.MC1Value.CheckBox.Value == 1,
                 obj.Parameters.MC1Enable = true;
                 obj.Handles.MC1Value.CheckBox.Value = 1;
             end
             if ~obj.Play,
                 obj.UpdateFrame;
             end
         else
             obj.Handles.MC1Value.Edit.String = num2str(obj.Parameters.MC1Value);
         end
     end
     
      function SFCB(obj)
         if obj.Handles.FilterSize.CheckBox.Value == 1,
             obj.Parameters.FilterSizeEnable = true;
         else
             obj.Parameters.FilterSizeEnable = false;
         end
         if ~obj.Play,
             obj.UpdateFrame;
         end
     end
     
     function SFEditCB(obj)
         Temp = str2double(obj.Handles.FilterSize.Edit.String);
         if Temp>=1 && rem(Temp,1) == 0,
             obj.Parameters.FilterSize = Temp;
             if ~obj.Handles.FilterSize.CheckBox.Value == 1,
                 obj.Parameters.FilterSizeEnable = true;
                 obj.Handles.FilterSize.CheckBox.Value = 1;
             end
             if ~obj.Play,
                 obj.UpdateFrame;
             end
         else
             obj.Handles.FilterSize.Edit.String = num2str(obj.Parameters.FilterSize);
         end
     end
         
      function MC2CB(obj)
         if obj.Handles.MC2Value.CheckBox.Value == 1,
             obj.Parameters.MC2Enable = true;
         else
             obj.Parameters.MC2Enable = false;
         end
         if ~obj.Play,
             obj.UpdateFrame;
         end
     end
     
     function MC2EditCB(obj)
         Temp = str2double(obj.Handles.MC2Value.Edit.String);
         if Temp>=1 && rem(Temp,1) == 0,
             obj.Parameters.MC2Value = Temp;
             obj.DefaultParameters.StructuringElement.MC2 = strel('disk',Temp);
             if ~obj.Handles.MC2Value.CheckBox.Value == 1,
                 obj.Parameters.MC2Enable = true;
                 obj.Handles.MC2Value.CheckBox.Value = 1;
             end
             if ~obj.Play,
                 obj.UpdateFrame;
             end
         else
             obj.Handles.MC2Value.Edit.String = num2str(obj.Parameters.MC2Value);
         end
     end
     
      function MO1CB(obj)
         if obj.Handles.MO1Value.CheckBox.Value == 1,
             obj.Parameters.MO1Enable = true;
         else
             obj.Parameters.MO1Enable = false;
         end
         if ~obj.Play,
             obj.UpdateFrame;
         end
     end
     
     function MO1EditCB(obj)
         Temp = str2double(obj.Handles.MO1Value.Edit.String);
         if Temp>=1 && rem(Temp,1) == 0,
             obj.Parameters.MO1Value = Temp;
             obj.DefaultParameters.StructuringElement.MO1 = strel('disk',Temp);
             if ~obj.Handles.MO1Value.CheckBox.Value == 1,
                 obj.Parameters.MO1Enable = true;
                 obj.Handles.MO1Value.CheckBox.Value = 1;
             end
             if ~obj.Play,
                 obj.UpdateFrame;
             end
         else
             obj.Handles.MO1Value.Edit.String = num2str(obj.Parameters.MO1Value);
         end
     end
     
      function SmoothContourCB(obj)
         if obj.Handles.SmoothContour.CheckBox.Value == 1,
             obj.Parameters.SmoothContourEnable = true;
         else
             obj.Parameters.SmoothContourEnable = false;
         end
         if ~obj.Play,
             obj.UpdateFrame;
         end
     end
     
     function SmoothContourEditCB(obj)
         Temp = str2double(obj.Handles.SmoothContour.Edit.String);
         if Temp>=1 && rem(Temp,1) == 0,
             obj.Parameters.SmoothContourValue = Temp;
             if ~obj.Handles.SmoothContour.CheckBox.Value == 1,
                 obj.Parameters.SmoothContourEnable = true;
                 obj.Handles.SmoothContour.CheckBox.Value = 1;
             end
             if ~obj.Play,
                 obj.UpdateFrame;
             end
         else
             obj.Handles.SmoothContour.Edit.String = num2str(obj.Parameters.SmoothContourValue);
         end
     end
     
     
        function DisableAll(obj)
            % Enable
            AllEnable = findobj(obj.Figure,'-property', 'Enable');
            while strcmpi(class(AllEnable),'matlab.ui.control.WebComponent')
                % There is a ROI menu last - that's a problem
                AllEnable = AllEnable(1:end-1);
            end
            obj.UIResponsiveness.Enable = {AllEnable.Enable};
            set(AllEnable,'Enable','off')

            % Taking care of the other callbacks
            AllEnable = findobj(obj.Figure.Children(:),'-property', 'ButtonDownFcn');
            obj.UIResponsiveness.CB = cell(numel(AllEnable),1);
            for C = 1 : numel(AllEnable),
                obj.UIResponsiveness.CB{C} = AllEnable(C).ButtonDownFcn;
                set(AllEnable(C),'ButtonDownFcn',[])
            end
            obj.Handles.CancelButton.Enable = 'on';
            obj.Handles.SetDefaultPathButton.Enable = 'on';
            obj.Handles.LoadFileButton.Enable = 'on';
            drawnow
        end
        
 
     function obj = EnableAll(obj)
         % Enable
         AllEnable = findobj(obj.Figure,'-property', 'Enable');
         arrayfun(@(x) set(AllEnable(x),'Enable',obj.UIResponsiveness.Enable{x}),1:numel(AllEnable))
         
         % Taking care of the other callbacks
         AllEnable = findobj(obj.Figure.Children(:),'-property', 'ButtonDownFcn');
         for C = 1 : numel(obj.UIResponsiveness.CB), % Counting only up to the number before disabling, plots might have been added
             set(AllEnable(C),'ButtonDownFcn',obj.UIResponsiveness.CB{C})
         end

        % Special adjustement for the background substraction (double
        % conditionality...)
        if obj.Parameters.BackGround.Enable == 1 & ~isempty(obj.Parameters.BackGround.Image),
            obj.Handles.BackGroundEnable.Enable = 'on';
            if  obj.Handles.BackGroundEnable.Value == 1,
                obj.Handles.ShowSubstracted.Enable = 'on';
            else
                obj.Handles.ShowSubstracted.Enable = 'off';
            end
        else
            obj.Handles.BackGroundEnable.Enable = 'off';
            obj.Handles.ShowSubstracted.Enable = 'off';
        end
        drawnow
     end
     
     function AddToBatchCB(obj)
         if ~isempty(obj.BatchFiles),
             if ~(any(strcmpi(obj.BatchFiles(:,1),obj.CurrentFile) & (strcmpi(obj.BatchFiles(:,3),obj.Parameters.VideoMode)))),
                 if exist(obj.TrackingLogFile,'File')
                     TrackingLog = load(obj.TrackingLogFile);
                 end
                 obj.BatchFiles = [obj.BatchFiles; {obj.CurrentFile},{obj.TrackingLogFile},{obj.Parameters.VideoMode},{obj.Basename}];
                 [~,Ind] = sort(obj.BatchFiles(:,4));
                 obj.BatchFiles = obj.BatchFiles(Ind,:);
                 TrackingLog.(obj.Parameters.VideoMode).TempParameters = obj.Parameters;
                 save(obj.TrackingLogFile,'-struct','TrackingLog')
             end
         else
             if exist(obj.TrackingLogFile,'File')
                 TrackingLog = load(obj.TrackingLogFile);
             end
             obj.BatchFiles = [{obj.CurrentFile},{obj.TrackingLogFile},{obj.Parameters.VideoMode},{obj.Basename}];
             TrackingLog.(obj.Parameters.VideoMode).TempParameters = obj.Parameters;
             save(obj.TrackingLogFile,'-struct','TrackingLog')
         end
     end
     
     function EditBatchListCB(obj)
         if ~isempty(obj.BatchFiles)
             [Index, Tf] = listdlg('ListString',obj.BatchFiles(:,4),'PromptString',['Select files to remove from the batch.' {''}]);
             if Tf,
                 Indx = true([length(obj.BatchFiles(:,1)),1]);
                 Indx(Index) = false;
                 obj.BatchFiles = obj.BatchFiles(Indx,:);
             end
         end
     end
     
     function ProcessCB(obj)
         obj.DisableAll;
         obj.Handles.SetDefaultPathButton.Enable = 'off';
         obj.Handles.LoadFileButton.Enable = 'off';
         drawnow
         BatchFiles = obj.BatchFiles;
        
        parfor P = 1 : length(BatchFiles(:,1)),
             disp([BatchFiles{P,4} ' starting...'])
             try
                 TrackingLog = load(BatchFiles{P,2});
                 CurrObj = obj;
                 CurrObj.Basename = BatchFiles{P,4};
                 CurrObj.CurrentFile = BatchFiles{P,1};
                 CurrObj.TrackingLogFile = BatchFiles{P,2};
                 CurrObj.Parameters = TrackingLog.(BatchFiles{P,3}).TempParameters;
                 CurrObj.Movie = VideoReader(BatchFiles{P,1});
                 CurrObj.Movie.CurrentTime = 0;
                 
                 FrameNumEstimate = round(1.1 * CurrObj.Movie.Duration*CurrObj.Movie.FrameRate);   % VideoReader NumberOfFrames was reported to be sometimes inacurate
%                  MaskContour = cell(FrameNumEstimate,1); % Takes too much
%                  space to keep everything
                 MaskContour = cell(2,1);
                 Contour = cell(FrameNumEstimate,1);
                 Center_G = NaN([FrameNumEstimate 2]);
                 MaskPixels = NaN(FrameNumEstimate,1);
                 MotionMeasure = NaN(FrameNumEstimate,1);
                 Times = NaN(FrameNumEstimate,1);
                 FrameCount = 0;
                 tic
                 TrueMask = true([CurrObj.Movie.Height CurrObj.Movie.Width]);
                 while CurrObj.Movie.hasFrame,
                     FrameCount = FrameCount + 1;
                     [closeBW,CC] = obj.ProcessFrame('Process');
                     Times(FrameCount) = CurrObj.CurrentTime;
                     if ~isnan(closeBW),
                         MaskContour{1} = MaskContour{2};
                         MaskContour{2} = closeBW;
                         MaskPixels(FrameCount) = numel(closeBW(closeBW==1));
                         Contour{FrameCount} = [CC,CC(:,1)];
                         Meas = regionprops(closeBW,'Centroid');
                         Center_G(FrameCount,:) = Meas(1).Centroid;
                         if FrameCount>1,
                             if ~isnan(MaskContour{1})
                                 MotionMeasure(FrameCount) = 100*numel(TrueMask((MaskContour{2} & ~MaskContour{1})))/MaskPixels(FrameCount-1);
                             end
                         end
                     else
                         Contour{FrameCount} = [NaN;NaN];
                         Center_G(FrameCount,:) = [NaN NaN];
                         MaskPixels(FrameCount) = NaN;
                         %                          MaskContour{FrameCount} = NaN;
                         MaskContour{2} = NaN;
                     end
                 end
                 Contour = Contour(1:FrameCount);
                 Center_G = Center_G(1:FrameCount,:);
                 MotionMeasure = MotionMeasure(1:FrameCount,1);
                 Times = Times(1:FrameCount,1);
                 TrackingLog = load(BatchFiles{P,2}); % Reload in case we have parallel processings
                 %(e.g. RGB on one side and Thermal on the other)
                 TrackingLog.(CurrObj.Parameters.VideoMode).Contour = Contour;
                 TrackingLog.(CurrObj.Parameters.VideoMode).Center = Center_G;
                 TrackingLog.(CurrObj.Parameters.VideoMode).MotionMeasure = MotionMeasure;
                 TrackingLog.(CurrObj.Parameters.VideoMode).Parameters = TrackingLog.(CurrObj.Parameters.VideoMode).TempParameters;
                 TrackingLog.(CurrObj.Parameters.VideoMode).MovieTimes = Times;
                 if strcmpi(CurrObj.Parameters.VideoMode,'RGB'),
                     [Path,Name,~] = fileparts(BatchFiles{P,1});
                     MM_File = [Path '\' Name '.DVT'];
                     if exist(MM_File,'file'),
                         DVTRead = csvread(MM_File);
                         TrackingLog.(CurrObj.Parameters.VideoMode).Times = DVTRead(:,2);
                     end
                 end
                 obj.SaveLog(TrackingLog,BatchFiles{P,2});
                 toc
             catch
                 disp([BatchFiles{P,4} ' failed...'])
             end
             disp([BatchFiles{P,4} ' finished!'])
         end
         % Flush the batch list
         obj.BatchFiles = {};
         obj.EnableAll;
     end
     
     function SaveLog(obj,TrackingLog,TrackingLogFile)
         save(TrackingLogFile,'-struct','TrackingLog')
     end
     
     function BackGroundProcessCB(obj)
         obj.Play = false;
         %% Create temporary GUI and hide the main GUI
         Scrsz = get(0,'ScreenSize');
         obj.Figure.Visible = 'off';
         obj.BackGroundFigure = figure('Position',[Scrsz(3)/10 45 3/5*Scrsz(3) Scrsz(4)-75],'MenuBar','none');

         % Duplicate the movie object and plot the first frame
         obj.BackGroundMovie = obj.Movie;
         obj.BackGroundMovie.CurrentTime = 0;
         
         % Duplicate the background infos (replaces the main background IF validated
         obj.Parameters.BackGroundTemp = obj.Parameters.BackGround;
         
         obj.HandlesBG.SubstractCheckBox = uicontrol('Style','checkbox','String','Substract background','Value',0,'FontSize',obj.FontScaling*13,'FontName','Arial','FontWeight','bold',...
             'Value',obj.Parameters.BackGround.Substract,'Callback',{@(~,~)obj.SubstractCB},'Units','Normalized','Position',[0.075 0.925 0.2 0.03],'HorizontalAlignment','left');
         
         obj.BackGroundSubMovie = subplot('Position',[0.075 0.525 0.45 0.4]);
         if size(obj.BackGroundMovie.readFrame,3)>1,
             image(obj.BackGroundMovie.readFrame,'Parent',obj.BackGroundSubMovie);
         else
             imagesc(obj.BackGroundMovie.readFrame,'Parent',obj.BackGroundSubMovie);
         end
         obj.BackGroundMovie.CurrentTime = 0;
         obj.Parameters.BackGroundTemp.CurrentTime = 0;

         obj.BackGroundSubMovie.XColor = 'none';
         obj.BackGroundSubMovie.YColor = 'none';
         obj.BackGroundSub = subplot('Position',[0.075 0.075 0.45 0.4]);
         if ~isempty(obj.Parameters.BackGround.Image),
             if ismatrix(obj.Parameters.BackGround.Image),
                 imagesc(obj.Parameters.BackGround.Image,'Parent',obj.BackGroundSub);
             else
                 image(obj.Parameters.BackGround.Image,'Parent',obj.BackGroundSub);
             end
             if obj.Parameters.BackGround.Substract,
                 obj.BackGroundSubMovie.Children.CData = 255-uint8(255+double(obj.BackGroundSubMovie.Children.CData)- double(obj.Parameters.BackGround.Image));
                 obj.BackGroundSubMovie.CLim = [0 255];
             end
         else
             image([0 0;0 0],'Parent',obj.BackGroundSub);
         end
         obj.BackGroundSub.XColor = 'none';
         obj.BackGroundSub.YColor = 'none';
         
         obj.BackGroundSubSlider = subplot('Position',[obj.BackGroundSubMovie.Position(1) 0.525-0.03 obj.BackGroundSubMovie.Position(3) 0.03]);
         obj.BackGroundSubSlider.Color = [0.975 0.975 0.975];
         obj.BackGroundSliderLine = plot([0 0],[0 1],'Color','k','LineWidth',3.5,'ButtonDownFcn',{@(~,~)obj.SlideBackGround});
         obj.BackGroundSubSlider.YColor = 'none';
         obj.BackGroundSubSlider.XColor = 'none';
         obj.BackGroundSubSlider.XLim = [-0.5 obj.Movie.Duration+0.5];
         obj.BackGroundSubSlider.YLim = [0 1];
         if ~verLessThan('matlab','9.5')
             obj.BackGroundSubSlider.Toolbar.Visible = 'off';
             disableDefaultInteractivity(obj.BackGroundSubSlider);
         end
         
         obj.BackGroundSubMarkers = subplot('Position',[obj.BackGroundSubMovie.Position(1) 0.475 obj.BackGroundSubMovie.Position(3) 0.02]);
         obj.BackGroundSubMarkers.Color = 'none';
         obj.BackGroundSubMarkers.YColor = 'none';
         obj.BackGroundSubMarkers.XColor = 'none';
         obj.BackGroundSubMarkers.XLim = [-0.5 obj.Movie.Duration+0.5];
         obj.BackGroundSubMarkers.YLim = [0 1];
         if ~verLessThan('matlab','9.5')
             obj.BackGroundSubMarkers.Toolbar.Visible = 'off';
             disableDefaultInteractivity(obj.BackGroundSubMarkers);
         end
         hold(obj.BackGroundSubMarkers,'on');

         if ~isempty(obj.Parameters.BackGround.PickedTimes),
             hold(obj.BackGroundSubSlider,'on')
             obj.BackGroundFrameLines = arrayfun(@(x) plot([obj.Parameters.BackGround.PickedTimes(x) obj.Parameters.BackGround.PickedTimes(x)],[0 1],'Color',[0 0.45 0.74],'Parent',obj.BackGroundSubSlider,'LineWidth',1.5,'ButtonDownFcn',{@(src,evt)obj.EditBackGroundFrame(src,evt)},'Tag',num2str(x)),1:numel(obj.Parameters.BackGround.PickedTimes));
             hold(obj.BackGroundSubSlider,'off')
             uistack(obj.BackGroundSliderLine,'top');
         else
             obj.BackGroundFrameLines = [];
         end
         
          ModeLegend = uicontrol('Style','text','String','Processing mode','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
                 'Units','Normalized','Position',[0.55 0.885 0.2 0.04],'HorizontalAlignment','left');

         obj.HandlesBG.MedianButton = uicontrol('Style','togglebutton','String','Median','Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.BackGroundMedianCB},'Units','Normalized','Position',[0.6 0.84 0.07 0.04]);
         obj.HandlesBG.MeanButton = uicontrol('Style','togglebutton','String','Mean','Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.BackGroundMeanCB},'Units','Normalized','Position',[0.7 0.84 0.07 0.04]);
         obj.HandlesBG.MinButton = uicontrol('Style','togglebutton','String','Min','Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.BackGroundMinCB},'Units','Normalized','Position',[0.6 0.7975 0.07 0.04]);
         obj.HandlesBG.MaxButton = uicontrol('Style','togglebutton','String','Max','Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.BackGroundMaxCB},'Units','Normalized','Position',[0.7 0.7975 0.07 0.04]);
         obj.HandlesBG.PrctileButton = uicontrol('Style','togglebutton','String','Prctile','Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.BackGroundPrctileCB},'Units','Normalized','Position',[0.6 0.73 0.07 0.04]);
         obj.HandlesBG.PrctileValue = uicontrol('Style','edit','String',num2str(obj.Parameters.BackGround.Prctile),'FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.BackGroundPrctileEdit},'Enable','off','Units','Normalized','Position',[0.7 0.73 0.07 0.04],'HorizontalAlignment','center');
         
         obj.BackGroundSubSliderPrctile = subplot('Position',[0.8 0.73 0.15 0.04]);
         obj.BackGroundSubSliderPrctile.Color = [0.975 0.975 0.975];
         obj.BackGroundSliderPrctileLine = plot([obj.Parameters.BackGround.Prctile obj.Parameters.BackGround.Prctile],[0 1],'Color','k','LineWidth',3.5,'ButtonDownFcn',{@(~,~)obj.SlideBackGroundPrctile});
         obj.BackGroundSubSliderPrctile.YColor = 'none';
         obj.BackGroundSubSliderPrctile.XColor = 'none';
         obj.BackGroundSubSliderPrctile.XLim = [0 100];
         obj.BackGroundSubSliderPrctile.YLim = [0 1];
         if ~verLessThan('matlab','9.5')
             obj.BackGroundSubSliderPrctile.Toolbar.Visible = 'off';
             disableDefaultInteractivity(obj.BackGroundSubSliderPrctile);
         end
         
         switch obj.Parameters.BackGround.Mode,
             case 'Median'
                 obj.HandlesBG.MedianButton.Value = 1;
             case 'Mean'
                 obj.HandlesBG.MeanButton.Value = 1;
             case 'Min'
                 obj.HandlesBG.MedianButton.Value = 1;
             case 'Max'
                 obj.HandlesBG.MedianButton.Value = 1;
             case 'Prctile'
                 obj.HandlesBG.PrctileButton.Value = 1;
                 obj.HandlesBG.PrctileValue.Enable = 'on';
                 obj.BackGroundSliderPrctileLine.ButtonDownFcn = {@(~,~)obj.SlideBackGroundPrctile};
         end
         
         % Auto frame picking
         FramePickingLegend = uicontrol('Style','text','String','Automatic frames selection','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
             'Units','Normalized','Position',[0.55 0.65 0.25 0.04],'HorizontalAlignment','left');
         FrameNumberLegend = uicontrol('Style','text','String','Number of frames to pick','FontSize',obj.FontScaling*13,'FontName','Arial','FontWeight','bold',...
             'Units','Normalized','Position',[0.6 0.595 0.2 0.04],'HorizontalAlignment','left');
         obj.HandlesBG.FramesValue = uicontrol('Style','edit','String',num2str(obj.Parameters.BackGround.FramesNum),'FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.BackGroundFramesNumEdit},'Units','Normalized','Position',[0.8 0.605 0.07 0.04],'HorizontalAlignment','center');
         obj.HandlesBG.ExtractButton = uicontrol('Style','pushbutton','String','Extract frames','Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.BackGroundExtractFramesCB},'Units','Normalized','Position',[0.6 0.56 0.18 0.04]);
         
         % Manual frame picking
         ManualFramePickingLegend = uicontrol('Style','text','String','Manual frames selection','FontSize',obj.FontScaling*16,'FontName','Arial','FontWeight','bold',...
             'Units','Normalized','Position',[0.55 0.435 0.25 0.04],'HorizontalAlignment','left');
         obj.HandlesBG.RemoveAllButton = uicontrol('Style','pushbutton','String','Reset selection','Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.BackGroundRemoveAllFramesCB},'Units','Normalized','Position',[0.6 0.39 0.18 0.04]);
         obj.HandlesBG.NextPickedFrameButton = uicontrol('Style','pushbutton','String','Remove current','Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.BackGroundRemoveFrameCB},'Units','Normalized','Position',[0.6 0.34 0.18 0.04]);
         obj.HandlesBG.PreviousFrameButton = uicontrol('Style','pushbutton','String','Previous','Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.BackGroundPreviousFrameCB},'Units','Normalized','Position',[0.6 0.29 0.09 0.04]);
         obj.HandlesBG.NextFrameButton = uicontrol('Style','pushbutton','String','Next','Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.BackGroundNextFrameCB},'Units','Normalized','Position',[0.69 0.29 0.09 0.04]);
         obj.HandlesBG.PickFrameButton = uicontrol('Style','pushbutton','String','Pick displayed','Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.BackGroundPickFrameCB},'Units','Normalized','Position',[0.6 0.24 0.18 0.04]);

         % Validate/exit
         
         obj.HandlesBG.ProcessButton = uicontrol('Style','pushbutton','String','Process','Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.ProcessBackGround},'Units','Normalized','Position',[0.6 0.135 0.18 0.05]);
         obj.HandlesBG.CancelButton = uicontrol('Style','pushbutton','String','Cancel & exit','Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.CancelCB},'Units','Normalized','Position',[0.6 0.075 0.18 0.05]);
         obj.HandlesBG.ValidateButton = uicontrol('Style','pushbutton','String','Validate','Value',0,'FontSize',obj.FontScaling*14,'FontName','Arial','FontWeight','bold',...
             'Callback',{@(~,~)obj.ValidateBackGround},'Units','Normalized','Position',[0.8 0.075 0.18 0.05]);
      
         obj.HandlesBG.Selected = [];
         obj.HandlesBG.SelectedMarker = [];
     end
     
     function EditBackGroundMarkerCB(obj,~)
             obj.HandlesBG.Selected = [];
             delete(obj.HandlesBG.SelectedMarker);
     end
     
     function BackGroundRemoveFrameCB(obj,~)
         if ~isempty(obj.HandlesBG.Selected),
             Indx = str2double(obj.HandlesBG.Selected.Tag);
             obj.Parameters.BackGroundTemp.PickedTimes(Indx) = [];
             obj.Parameters.BackGroundTemp.PickedTimes = sort(obj.Parameters.BackGroundTemp.PickedTimes);
             obj.Parameters.BackGroundTemp.PickedTimes = unique(obj.Parameters.BackGroundTemp.PickedTimes);
             % Plot on the slider
             if ~isempty(obj.BackGroundFrameLines)
                 delete(obj.BackGroundFrameLines);
             end
             hold(obj.BackGroundSubSlider,'on')
             delete(obj.HandlesBG.SelectedMarker);
             obj.HandlesBG.Selected = [];
             obj.HandlesBG.SelectedMarker = [];
             obj.BackGroundFrameLines = arrayfun(@(x) plot([obj.Parameters.BackGroundTemp.PickedTimes(x) obj.Parameters.BackGroundTemp.PickedTimes(x)],[0 1],'Color',[0 0.45 0.74],'Parent',obj.BackGroundSubSlider,'LineWidth',1.5,'ButtonDownFcn',{@(src,evt)obj.EditBackGroundFrame(src,evt)},'Tag',num2str(x)),1:numel(obj.Parameters.BackGroundTemp.PickedTimes));
             hold(obj.BackGroundSubSlider,'off')
             uistack(obj.BackGroundSliderLine,'top');
             drawnow
         end
     end
     
     function EditBackGroundFrame(obj,src,~)
         if ~isempty(obj.HandlesBG.Selected),
             if strcmpi(src.Tag,obj.HandlesBG.Selected.Tag),
                 obj.HandlesBG.Selected = [];
                 delete(obj.HandlesBG.SelectedMarker);
             else
                 DefaultColors;
                 CurrTime = obj.Parameters.BackGroundTemp.PickedTimes(str2double(src.Tag));
                 obj.HandlesBG.SelectedMarker.XData = CurrTime;
                 obj.HandlesBG.SelectedMarker.Tag = src.Tag;
                 obj.HandlesBG.Selected = src;
                 obj.BackGroundMovie.CurrentTime = CurrTime;
                 obj.BackGroundSliderLine.XData = [CurrTime CurrTime];
                  if obj.Parameters.BackGroundTemp.Substract && ~isempty(obj.Parameters.BackGroundTemp.Image),
                      if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                          obj.BackGroundSubMovie.Children.CData = 255-uint8(255+double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                      else
                          obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                      end
                  else
                      if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                          obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
                      else
                          obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
                      end
                  end
             end
         else
             DefaultColors;
             CurrTime = obj.Parameters.BackGroundTemp.PickedTimes(str2double(src.Tag));
             obj.HandlesBG.SelectedMarker = plot(CurrTime,0.5,'^','MarkerSize',9,'MarkerFaceColor',Colors(1,:),'Color',Colors(1,:),'Parent',obj.BackGroundSubMarkers,'ButtonDownFcn',{@(~,~)obj.EditBackGroundMarkerCB},'Tag',src.Tag);
             obj.HandlesBG.Selected = src;
             obj.BackGroundMovie.CurrentTime = CurrTime;
             obj.BackGroundSliderLine.XData = [CurrTime CurrTime];
             if obj.Parameters.BackGroundTemp.Substract && ~isempty(obj.Parameters.BackGroundTemp.Image),
                 if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                     obj.BackGroundSubMovie.Children.CData = 255-uint8(255+double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                 else
                     obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                 end
             else
                 if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                     obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
                 else
                     obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
                 end
             end
         end
     end
     
     function BackGroundPickFrameCB(obj)
         ToAdd = obj.BackGroundMovie.CurrentTime;
         if ~any(obj.Parameters.BackGroundTemp.PickedTimes == ToAdd),
             obj.Parameters.BackGroundTemp.PickedTimes(end+1) = ToAdd;
         end
         obj.Parameters.BackGroundTemp.PickedTimes = sort(obj.Parameters.BackGroundTemp.PickedTimes);
         obj.Parameters.BackGroundTemp.PickedTimes = unique(obj.Parameters.BackGroundTemp.PickedTimes);
         % Plot on the slider
         if ~isempty(obj.BackGroundFrameLines)
             delete(obj.BackGroundFrameLines);
         end
         hold(obj.BackGroundSubSlider,'on')
         delete(obj.HandlesBG.SelectedMarker);
         obj.HandlesBG.Selected = [];
         obj.HandlesBG.SelectedMarker = [];
         obj.BackGroundFrameLines = arrayfun(@(x) plot([obj.Parameters.BackGroundTemp.PickedTimes(x) obj.Parameters.BackGroundTemp.PickedTimes(x)],[0 1],'Color',[0 0.45 0.74],'Parent',obj.BackGroundSubSlider,'LineWidth',1.5,'ButtonDownFcn',{@(src,evt)obj.EditBackGroundFrame(src,evt)},'Tag',num2str(x)),1:numel(obj.Parameters.BackGroundTemp.PickedTimes));
         hold(obj.BackGroundSubSlider,'off')
         uistack(obj.BackGroundSliderLine,'top');
         drawnow
     end
     
     function BackGroundPreviousFrameCB(obj)
         if ~isempty(obj.HandlesBG.Selected),
             if str2double(obj.HandlesBG.SelectedMarker.Tag) ~= 1,
                 DefaultColors;
                 CurrTime = obj.Parameters.BackGroundTemp.PickedTimes(str2double(obj.BackGroundFrameLines(str2double(obj.HandlesBG.Selected.Tag)-1).Tag));
                 obj.HandlesBG.SelectedMarker.Tag = num2str(str2double(obj.HandlesBG.Selected.Tag)-1);
                 obj.HandlesBG.SelectedMarker.XData = CurrTime;
                 obj.HandlesBG.Selected = obj.BackGroundFrameLines(str2double(obj.HandlesBG.Selected.Tag)-1);
                 obj.BackGroundMovie.CurrentTime = CurrTime;
                 obj.BackGroundSliderLine.XData = [CurrTime CurrTime];
                 if obj.Parameters.BackGroundTemp.Substract && ~isempty(obj.Parameters.BackGroundTemp.Image),
                     if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                         obj.BackGroundSubMovie.Children.CData = 255-uint8(255+double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                     else
                         obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                     end
                 else
                     if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                         obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
                     else
                         obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
                     end
                 end
             end
         else
             if ~isempty(obj.Parameters.BackGroundTemp.PickedTimes),
                 IndexPrev = find(obj.Parameters.BackGroundTemp.PickedTimes<obj.BackGroundSliderLine.XData(1),1,'last');
                 if isempty(IndexPrev),
                     IndexPrev = numel(obj.BackGroundFrameLines);
                 end
                 DefaultColors;
                 CurrTime = obj.Parameters.BackGroundTemp.PickedTimes(IndexPrev);
                 obj.HandlesBG.SelectedMarker = plot(CurrTime,0.5,'^','MarkerSize',9,'MarkerFaceColor',Colors(1,:),'Color',Colors(1,:),'Parent',obj.BackGroundSubMarkers,'ButtonDownFcn',{@(~,~)obj.EditBackGroundMarkerCB},'Tag',num2str(IndexPrev));
                 obj.HandlesBG.Selected = obj.BackGroundFrameLines(IndexPrev);
                 obj.BackGroundMovie.CurrentTime = CurrTime;
                 obj.BackGroundSliderLine.XData = [CurrTime CurrTime];
                 if obj.Parameters.BackGroundTemp.Substract && ~isempty(obj.Parameters.BackGroundTemp.Image),
                     if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                         obj.BackGroundSubMovie.Children.CData = 255-uint8(255+double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                     else
                         obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                     end
                 else
                     if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                         obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
                     else
                         obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
                     end
                 end
             end
         end
     end
     
     
     function BackGroundNextFrameCB(obj)
         if ~isempty(obj.HandlesBG.Selected),
             if str2double(obj.HandlesBG.SelectedMarker.Tag) ~= numel(obj.BackGroundFrameLines),
                 DefaultColors;
                 CurrTime = obj.Parameters.BackGroundTemp.PickedTimes(str2double(obj.BackGroundFrameLines(str2double(obj.HandlesBG.Selected.Tag)+1).Tag));
                 obj.HandlesBG.SelectedMarker.Tag = num2str(str2double(obj.HandlesBG.Selected.Tag)+1);
                 obj.HandlesBG.SelectedMarker.XData = CurrTime;
                 obj.HandlesBG.Selected = obj.BackGroundFrameLines(str2double(obj.HandlesBG.Selected.Tag)+1);
                 obj.BackGroundMovie.CurrentTime = CurrTime;
                 obj.BackGroundSliderLine.XData = [CurrTime CurrTime];
                 if obj.Parameters.BackGroundTemp.Substract && ~isempty(obj.Parameters.BackGroundTemp.Image),
                     if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                         obj.BackGroundSubMovie.Children.CData = 255-uint8(255+double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                     else
                         obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                     end
                 else
                     if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                         obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
                     else
                         obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
                     end
                 end
             end
         else
             if ~isempty(obj.Parameters.BackGroundTemp.PickedTimes),
                 DefaultColors;
                IndexPrev = find(obj.Parameters.BackGroundTemp.PickedTimes>obj.BackGroundSliderLine.XData(1),1,'first');
                 if isempty(IndexPrev),
                     IndexPrev = 1;
                 end
                 DefaultColors;
                 CurrTime = obj.Parameters.BackGroundTemp.PickedTimes(IndexPrev);
                 obj.HandlesBG.SelectedMarker = plot(CurrTime,0.5,'^','MarkerSize',9,'MarkerFaceColor',Colors(1,:),'Color',Colors(1,:),'Parent',obj.BackGroundSubMarkers,'ButtonDownFcn',{@(~,~)obj.EditBackGroundMarkerCB},'Tag',num2str(IndexPrev));
                 obj.HandlesBG.Selected = obj.BackGroundFrameLines(IndexPrev);
                 obj.BackGroundMovie.CurrentTime = CurrTime;
                 obj.BackGroundSliderLine.XData = [CurrTime CurrTime];
                 if obj.Parameters.BackGroundTemp.Substract && ~isempty(obj.Parameters.BackGroundTemp.Image),
                     if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                         obj.BackGroundSubMovie.Children.CData = 255-uint8(255+double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                     else
                         obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                     end
                 else
                     if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                         obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
                     else
                         obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
                     end
                 end
             end
         end
     end
     
     function BackGroundRemoveAllFramesCB(obj)
         obj.Parameters.BackGroundTemp.PickedTimes = [];
         if ~isempty(obj.BackGroundFrameLines)
             delete(obj.BackGroundFrameLines);
         end
         if ~isempty(obj.HandlesBG.Selected),
             obj.HandlesBG.Selected = [];
             delete(obj.HandlesBG.SelectedMarker);
             obj.HandlesBG.SelectedMarker = [];
         end
     end
     
     function BackGroundEnableCB(obj)
         if obj.Handles.BackGroundEnable.Value,
             if isempty(obj.Parameters.BackGround.Image)
                 obj.Handles.BackGroundEnable.Value = 0;
                 obj.Parameters.BackGround.Enable = 0;
                 obj.Handles.BackGroundEnable.Enable = 'off';
                 obj.Handles.ShowSubstracted.Enable = 'off';
             else
                 obj.Parameters.BackGround.Enable = 1;
                 obj.Handles.ShowSubstracted.Enable = 'on';
                 if obj.Handles.ShowSubstracted.Value,
                     obj.Parameters.BackGround.SubstractMain = 1;
                 end
                 obj.UpdateFrame;
             end
         else
             obj.Parameters.BackGround.Enable = 0;
             obj.Handles.ShowSubstracted.Enable = 'off';
             obj.Parameters.BackGround.SubstractMain = 0;
             obj.UpdateFrame;
         end
     end
     
     function SubstractCB(obj)
         obj.Parameters.BackGroundTemp.Substract = obj.HandlesBG.SubstractCheckBox.Value;
         obj.Parameters.BackGroundTemp.CurrentTime = obj.BackGroundMovie.CurrentTime;
         if obj.Parameters.BackGroundTemp.Substract && ~isempty(obj.Parameters.BackGroundTemp.Image),
             if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                 obj.BackGroundSubMovie.Children.CData = 255-uint8(255+double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
             else
                 obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
             end
         else
             if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                 obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
             else
                 obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
             end
         end
         drawnow
     end
     
     function ShowSubstractedCB(obj)
         if obj.Handles.ShowSubstracted.Value,
             obj.Parameters.BackGround.SubstractMain = 1;
         else
             obj.Parameters.BackGround.SubstractMain = 0;
         end
         obj.UpdateFrame;
     end
     
     function BackGroundExtractFramesCB(obj)
         % Just a rough estimate of the times to extract the frames
         obj.Parameters.BackGroundTemp.PickedTimes = 0:obj.BackGroundMovie.Duration/(obj.Parameters.BackGroundTemp.FramesNum-1):obj.BackGroundMovie.Duration-1;
         % Plot on the slider
         if ~isempty(obj.BackGroundFrameLines)
             delete(obj.BackGroundFrameLines);
         end
         if ~isempty(obj.HandlesBG.SelectedMarker),
             delete(obj.HandlesBG.SelectedMarker);
             obj.HandlesBG.SelectedMarker = [];
         end
         obj.HandlesBG.Selected = [];
         hold(obj.BackGroundSubSlider,'on')
         obj.BackGroundFrameLines = arrayfun(@(x) plot([obj.Parameters.BackGroundTemp.PickedTimes(x) obj.Parameters.BackGroundTemp.PickedTimes(x)],[0 1],'Color',[0 0.45 0.74],'Parent',obj.BackGroundSubSlider,'LineWidth',1.5,'ButtonDownFcn',{@(src,evt)obj.EditBackGroundFrame(src,evt)},'Tag',num2str(x)),1:numel(obj.Parameters.BackGroundTemp.PickedTimes));
         hold(obj.BackGroundSubSlider,'off')
         uistack(obj.BackGroundSliderLine,'top');
     end
     
     function BackGroundMedianCB(obj)
         if obj.HandlesBG.MedianButton.Value == 1,
             obj.HandlesBG.MeanButton.Value = 0;
             obj.HandlesBG.MinButton.Value = 0;
             obj.HandlesBG.MaxButton.Value = 0;
             obj.HandlesBG.PrctileButton.Value = 0;
             obj.Parameters.BackGroundTemp.Mode = 'Median';
             obj.HandlesBG.PrctileValue.Enable = 'off';
             obj.BackGroundSliderPrctileLine.ButtonDownFcn = {};
         else
             if strcmpi(obj.Parameters.BackGroundTemp.Mode,'Median'),
                 obj.HandlesBG.MedianButton.Value = 1;
             end
         end
         obj.ProcessBackGround;
     end
     function BackGroundMeanCB(obj)
         if obj.HandlesBG.MeanButton.Value == 1,
             obj.HandlesBG.MedianButton.Value = 0;
             obj.HandlesBG.MinButton.Value = 0;
             obj.HandlesBG.MaxButton.Value = 0;
             obj.HandlesBG.PrctileButton.Value = 0;
             obj.Parameters.BackGroundTemp.Mode = 'Mean';
             obj.HandlesBG.PrctileValue.Enable = 'off';
             obj.BackGroundSliderPrctileLine.ButtonDownFcn = {};
         else
             if strcmpi(obj.Parameters.BackGroundTemp.Mode,'Mean'),
                 obj.HandlesBG.MeanButton.Value = 1;
             end
         end
         obj.ProcessBackGround;
     end
     function BackGroundMinCB(obj)
         if obj.HandlesBG.MinButton.Value == 1,
             obj.HandlesBG.MeanButton.Value = 0;
             obj.HandlesBG.MedianButton.Value = 0;
             obj.HandlesBG.MaxButton.Value = 0;
             obj.HandlesBG.PrctileButton.Value = 0;
             obj.Parameters.BackGroundTemp.Mode = 'Min';
             obj.HandlesBG.PrctileValue.Enable = 'off';
             obj.BackGroundSliderPrctileLine.ButtonDownFcn = {};
         else
             if strcmpi(obj.Parameters.BackGroundTemp.Mode,'Min'),
                 obj.HandlesBG.MinButton.Value = 1;
             end
         end
         obj.ProcessBackGround;
     end
     function BackGroundMaxCB(obj)
         if obj.HandlesBG.MaxButton.Value == 1,
             obj.HandlesBG.MeanButton.Value = 0;
             obj.HandlesBG.MedianButton.Value = 0;
             obj.HandlesBG.MinButton.Value = 0;
             obj.HandlesBG.PrctileButton.Value = 0;
             obj.Parameters.BackGroundTemp.Mode = 'Max';
             obj.HandlesBG.PrctileValue.Enable = 'off';
             obj.BackGroundSliderPrctileLine.ButtonDownFcn = {};
         else
             if strcmpi(obj.Parameters.BackGroundTemp.Mode,'Max'),
                 obj.HandlesBG.MaxButton.Value = 1;
             end
         end
         obj.ProcessBackGround;
     end
     function BackGroundPrctileCB(obj)
         if obj.HandlesBG.PrctileButton.Value == 1,
             obj.HandlesBG.MeanButton.Value = 0;
             obj.HandlesBG.MedianButton.Value = 0;
             obj.HandlesBG.MaxButton.Value = 0;
             obj.HandlesBG.MinButton.Value = 0;
             obj.Parameters.BackGroundTemp.Mode = 'Prctile';
             obj.HandlesBG.PrctileValue.Enable = 'on';
             obj.BackGroundSliderPrctileLine.ButtonDownFcn = {@(~,~)obj.SlideBackGroundPrctile};
         else
             if strcmpi(obj.Parameters.BackGroundTemp.Mode,'Prctile'),
                 obj.HandlesBG.PrctileButton.Value = 1;
             end
         end
         obj.ProcessBackGround;
     end
     function BackGroundPrctileEdit(obj)
         obj.HandlesBG.PrctileValue.Enable = 'on';
         obj.BackGroundSliderPrctileLine.ButtonDownFcn = {@(~,~)obj.SlideBackGroundPrctile};
         CurrentP = str2double(obj.HandlesBG.PrctileValue.String);
         CurrentP = (round(CurrentP*10))/10;
         if CurrentP>0 && CurrentP<100,
             obj.BackGroundSliderPrctileLine.XData = [CurrentP CurrentP];
             obj.Parameters.BackGroundTemp.Prctile = CurrentP;
         else
             return
         end
         drawnow
     end
     
     
     function BackGroundFramesNumEdit(obj)
         CurrentP = str2double(obj.HandlesBG.FramesValue.String);
         CurrentP = round(CurrentP);
         if CurrentP>0 && CurrentP<(obj.BackGroundMovie.Duration*obj.BackGroundMovie.Framerate),
             obj.HandlesBG.FramesValue.String = num2str(CurrentP);
             obj.Parameters.BackGroundTemp.FramesNum = CurrentP;
         else
             obj.HandlesBG.FramesValue.String = num2str(obj.Parameters.BackGroundTemp.FramesNum);
             return
         end
         drawnow
     end
     
     function ProcessBackGround(obj)
         if ~isempty(obj.Parameters.BackGroundTemp.PickedTimes),
             obj.DisableAllBG;
             % If parallel computing: parallelise frame extraction
             % ('slight' overhead)
             DuplicatedMovie = obj.Movie;
             if ~DuplicatedMovie.hasFrame,
                 DuplicatedMovie.CurrentTime = obj.Movie.Duration - obj.Movie.Framerate;
             end
             
             ExtractedFrames = NaN([ obj.Movie.Height  obj.Movie.Width size(obj.Movie.readFrame,3) numel(obj.Parameters.BackGroundTemp.PickedTimes)]);
             parfor F = 1 : numel(obj.Parameters.BackGroundTemp.PickedTimes),
                 DuplicatedMovieF = DuplicatedMovie;
                 DuplicatedMovieF.CurrentTime = obj.Parameters.BackGroundTemp.PickedTimes(F)
                 ExtractedFrames(:,:,:,F) = DuplicatedMovie.readFrame;
             end
             
             BackGround = NaN([ obj.Movie.Height  obj.Movie.Width size(obj.Movie.readFrame,3)]);
             for D = 1 : size(obj.Movie.readFrame,3),
                 ChanD = squeeze(ExtractedFrames(:,:,D,:));
                 switch obj.Parameters.BackGroundTemp.Mode
                     case 'Median'
                         BackGround(:,:,D) = nanmedian(ChanD,3);
                     case 'Mean'
                         BackGround(:,:,D) = nanmean(ChanD,3);
                     case 'Min'
                         BackGround(:,:,D) = nanmin(ChanD,[],3);
                     case 'Max'
                         BackGround(:,:,D) = nanmax(ChanD,[],3);
                     case 'Prctile'
                         BackGround(:,:,D) = prctile(ChanD,obj.Parameters.BackGroundTemp.Prctile,3);
                 end
                 
             end
             
             obj.EnableAllBG;
             drawnow
             if D>1,
                 image(uint8(BackGround),'Parent',obj.BackGroundSub)
             else
                 imagesc(uint8(BackGround),'Parent',obj.BackGroundSub)
             end
             
             obj.Parameters.BackGroundTemp.Image = uint8(BackGround);
             if obj.Parameters.BackGroundTemp.Substract,
                 obj.BackGroundMovie.CurrentTime = obj.Parameters.BackGroundTemp.CurrentTime;
                 if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                     obj.BackGroundSubMovie.Children.CData = 255-uint8(255+double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                 else
                     obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                 end
             end
             obj.BackGroundSub.XColor = 'none';
             obj.BackGroundSub.YColor = 'none';
             drawnow
         end
     end
     
     function ValidateBackGround(obj)
         close(obj.BackGroundFigure)
         obj.Figure.Visible = 'on';
         
         obj.Handles.BackGroundEnable.Enable = 'on';
         obj.Parameters.BackGround = obj.Parameters.BackGroundTemp;
         if obj.Handles.BackGroundEnable.Value,
             obj.Parameters.BackGround.Enable = 1;
             obj.Handles.ShowSubstracted.Enable = 'on';
         else
             obj.Handles.ShowSubstracted.Enable = 'off';
         end
         obj.Parameters.BackGroundTemp = [];
         obj.UpdateFrame;
     end
     
     
     function SlideBackGround(obj)
         if ~isempty(obj.SubMovie),
             if ~obj.Dragging,
                 obj.HandlesBG.Selected = [];
                 if ~isempty(obj.HandlesBG.SelectedMarker)
                     delete(obj.HandlesBG.SelectedMarker);
                 end
                 obj.Dragging = true;
                 obj.BackGroundFigure.WindowButtonMotionFcn = @(~,~)obj.MovingTimeLineBackGround;
                 obj.BackGroundFigure.WindowButtonUpFcn = @(~,~)obj.SlideBackGround;
             else
                 obj.Dragging = false;
                 obj.BackGroundFigure.WindowButtonMotionFcn = [];
                 obj.BackGroundFigure.WindowButtonUpFcn = [];
             end
         end
     end
     
     function MovingTimeLineBackGround(obj)
         CurrentCursor = obj.BackGroundSubMovie.CurrentPoint(1);
         TempNewTime = CurrentCursor/obj.BackGroundSubMovie.XLim(2) * obj.BackGroundMovie.Duration;
         if TempNewTime>0 && TempNewTime<=obj.BackGroundMovie.Duration,
             obj.BackGroundSliderLine.XData = [TempNewTime TempNewTime];
         else
             return
         end
         if ~obj.Refractory,
             obj.Refractory = true;
             obj.Parameters.BackGroundTemp.CurrentTime = TempNewTime;
             obj.BackGroundMovie.CurrentTime = TempNewTime;
             if obj.Parameters.BackGroundTemp.Substract && ~isempty(obj.Parameters.BackGroundTemp.Image),
                 if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                     obj.BackGroundSubMovie.Children.CData = 255-uint8(255+double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                 else
                     obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame)- double(obj.Parameters.BackGroundTemp.Image));
                 end
             else
                 if strcmpi(obj.Parameters.MouseRelativeIntensity,'Low'),
                     obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
                 else
                     obj.BackGroundSubMovie.Children.CData = uint8(double(obj.BackGroundMovie.readFrame));
                 end
             end
             obj.Refractory = false;
         end
         drawnow
     end
     
     
     function SlideBackGroundPrctile(obj)
         if ~isempty(obj.Movie),
             if ~obj.Dragging,                
                 obj.Dragging = true;
                 obj.BackGroundFigure.WindowButtonMotionFcn = @(~,~)obj.MovingPrcentileLineBackGround;
                 obj.BackGroundFigure.WindowButtonUpFcn = @(~,~)obj.SlideBackGroundPrctile;
             else
                 obj.Dragging = false;
                 obj.BackGroundFigure.WindowButtonMotionFcn = [];
                 obj.BackGroundFigure.WindowButtonUpFcn = [];
             end
         end
     end
     
    
     function MovingPrcentileLineBackGround(obj)
         CurrentX = obj.BackGroundSubSliderPrctile.CurrentPoint(1);
         CurrentX = (round(CurrentX*10))/10;
         if CurrentX>0 && CurrentX<100,
             obj.BackGroundSliderPrctileLine.XData = [CurrentX CurrentX];
             obj.HandlesBG.PrctileValue.String = num2str(CurrentX);
             obj.Parameters.BackGroundTemp.Prctile = CurrentX;
         else
             return
         end
         drawnow
     end
          
     function  CancelCB(obj)
         close(obj.BackGroundFigure)
         obj.Figure.Visible = 'on';
         obj.Handles.BackGroundEnable.Enable = 'On';
         obj.Parameters.BackgroundTemp = [];
     end
     
     % Interactivity for BG figure
     function DisableAllBG(obj)
         % Enable
         AllEnable = findobj(obj.BackGroundFigure,'-property', 'Enable');
         obj.UIResponsiveness.Enable = {AllEnable.Enable};
         set(AllEnable,'Enable','off')
         
         % Taking care of the other callbacks
         AllEnable = findobj(obj.BackGroundFigure.Children(:),'-property', 'ButtonDownFcn');
         obj.UIResponsiveness.CB = cell(numel(AllEnable),1);
         for C = 1 : numel(AllEnable),
             obj.UIResponsiveness.CB{C} = AllEnable(C).ButtonDownFcn;
             set(AllEnable(C),'ButtonDownFcn',[])
         end
         drawnow
     end
     
     function obj = EnableAllBG(obj)
         % Enable
         AllEnable = findobj(obj.BackGroundFigure,'-property', 'Enable');
         arrayfun(@(x) set(AllEnable(x),'Enable',obj.UIResponsiveness.Enable{x}),1:numel(AllEnable))
         
         % Taking care of the other callbacks
         AllEnable = findobj(obj.BackGroundFigure.Children(:),'-property', 'ButtonDownFcn');
         for C = 1 : numel(obj.UIResponsiveness.CB), % Counting only up to the number before disabling, plots might have been added
             set(AllEnable(C),'ButtonDownFcn',obj.UIResponsiveness.CB{C})
         end
     end
     
     % Quitting     
     function AbortCB(obj)
         close all;
     end
     
     function delete(obj)
         % If we want to clean up some stuff
         %%%
         %
         
         disp('Destructor: OK')
     end
     
end


end
