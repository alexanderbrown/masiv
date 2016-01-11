classdef goggleViewer<handle
    
    properties(Access=protected)        
        %% Internal tracking
        numScrolls=0
        panxInt=0
        panyInt=0
        %% open plugin windows that override close requests
        openPluginsOverridingCloseReq={}
    end
    
    properties
        %% Handles to visible objects
        hFig
        hMainImgAx
        hAxContrastHist
        hAxContrastMin
        hAxContrastMax
        hjSliderContrast
        hAxContrastAuto
        
        infoPanels
        
        %% Menus
        mnuMain
        mnuImage
        mnuPlugins
        mnuTutPlugins

        %% Data
        mosaicInfo
        overviewDSS
        mainDisplay
        additionalDisplays
        contrastMode=0;
        dragOrigin=NaN;
        
    end
    
    events
        CacheChanged
        ViewChanged
        Scrolled
        Panned
        Zoomed
        CursorPositionChangedWithinImageAxes
        CursorPositionChangedOutsideImageAxes
        ViewClicked
        KeyPress
        ViewerClosing
    end
   
    methods % Constructor
        function obj=goggleViewer(mosaicInfoIn, idx)
            obj=obj@handle;
            %% Get mosaic info if none provided
            if verLessThan('matlab', '8.4.0')
              error('%s requires MATLAB 2014b or newer',mfilename)
            end
            
            %Add goggleViewer directories to the path
            goggleViewerPath = fileparts(which('goggleViewer'));
            goggleViewerDirs = fullfile(goggleViewerPath,'code');
            if isempty(strmatch(goggleViewerDirs,path)) %only add to path if dirs aren't already present
                fprintf('Adding goggleViewer to path for this session\n')
                addpath(genpath(goggleViewerDirs))
            end


            if nargin<1 ||isempty(mosaicInfoIn)
                fp=uigetdir(gbSetting('defaultDirectory'), 'Please select base directory of the stitched mosaic');
                if isempty(fp) || isnumeric(fp)
                    return
                end
                gbSetting('defaultDirectory', fileparts(fp))
                obj.mosaicInfo=TVStitchedMosaicInfo(fp);
            else
                obj.mosaicInfo=mosaicInfoIn;
            end
            
            %% Main UI object definitions
            obj.hFig=figure(...
                'Name', sprintf('GoggleBox: %s', obj.mosaicInfo.experimentName), ...
                'NumberTItle', 'off', ...
                'MenuBar', 'none', ...
                'Position', gbSetting('viewer.mainFigurePosition'), ...
                'Color', gbSetting('viewer.mainBkgdColor'), ...
                'ColorMap', gray(256), ...
                'KeyPressFcn', {@hFigMain_KeyPress, obj}, ...
                'KeyReleaseFcn', {@hFigMain_KeyRelease, obj}, ...
                'WindowButtonMotionFcn', {@mouseMove, obj}, ...
                'WindowScrollWheelFcn', {@hFigMain_ScrollWheel, obj}, ...
                'WindowButtonDownFcn', {@hFigMain_BtnDown, obj}, ...
                'WindowButtonUpFcn', {@hFigMain_BtnUp, obj}, ...
                'CloseRequestFcn', {@closeRequest, obj}, ...
                'BusyAction', 'cancel', 'Visible', 'off');
            obj.hMainImgAx=axes(...
                'Box', 'on', ...
                'YDir', 'reverse', ...
                'Color', [0 0 0], ...
                'XTick', [], 'YTick', [], ...
                'Position', [0.02 0.02 0.8 0.96], ...
                'ButtonDownFcn', {@handleMouseClick, obj});
            
            %% Menu Object declarations
            obj.mnuMain=uimenu(obj.hFig, 'Label', 'Main');
                    uimenu(obj.mnuMain, 'Label', 'Quit', 'Callback', {@closeRequest, obj})
                    
            obj.mnuImage=uimenu(obj.hFig, 'Label', 'Image');
                    uimenu(obj.mnuImage, 'Label', 'Export Current View to Workspace', ...
                                     'Callback', {@exportViewToWorkspace, obj})
                    uimenu(obj.mnuImage, 'Label', 'Detailed image processing steps...', ...
                                     'Callback', {@changeProcessingSteps, obj});
                    uimenu(obj.mnuImage, 'Label', 'Adjust precise XY position', ...
                                     'Callback', {@adjustXYPosClick, obj});
                                
            addPlugins(obj.mnuImage, obj, ['code',filesep,'resources',filesep,'corePlugins'], 1);

            
            obj.mnuPlugins=uimenu(obj.hFig, 'Label', 'Plugins');
                    addPlugins(obj.mnuPlugins, obj,['code',filesep,'plugins']);
                    
            obj.mnuTutPlugins=uimenu(obj.mnuPlugins,'label','Tutorials');
                    addPlugins(obj.mnuTutPlugins, obj,['code',filesep,'plugins',filesep,'tutorials'])

            %% Contrast adjustment object definitions
            obj.hAxContrastHist=axes(...
                'Box', 'on', ...
                'Color', gbSetting('viewer.panelBkgdColor'), ...
                'XTick', [], 'YTick', [], ...
                'Position', [0.83 0.89 0.16 0.09], ...
                'Color', [0.1 0.1 0.1]);
           
            sliderPanel=uipanel(...
                'Parent', obj.hFig, ...
                'Units', 'normalized', ...
                'Position', [0.83 0.81 0.16 0.07], ...
                'BackgroundColor', [0.1 0.1 0.1], ...
                'ForegroundColor', [0.8 0.8 0.8]);
            
             ppos=getpixelposition(sliderPanel);
             border=ppos(3:4)./[100 20]; border=[border border*2];
             
             obj.hjSliderContrast = com.jidesoft.swing.RangeSlider(-5000,15000,0,1000);  % min,max,low,high
             obj.hjSliderContrast = javacomponent(obj.hjSliderContrast, [border(1),border(2),ppos(3)-border(3),ppos(4)-border(4)], sliderPanel);
             
             set(obj.hjSliderContrast, 'MajorTickSpacing',5000, 'MinorTickSpacing',1000, 'PaintTicks',true, 'PaintLabels',true, ...
                 'Background',java.awt.Color(0.1, 0.1, 0.1), 'Foreground', java.awt.Color(0.8, 0.8, 0.8), ...
                 'StateChangedCallback',@(h,e) adjustContrast(h,e,obj));
            
            %% Get DSS if not specified. Load up and display
            if nargin<2||isempty(idx)
                obj.overviewDSS=selectDownscaledStack(obj.mosaicInfo);
                if isempty(obj.overviewDSS)
                    close(obj.hFig)
                    return
                end
            else
                obj.overviewDSS=obj.mosaicInfo.downscaledStacks(idx);
            end
            startDebugOutput;
            obj.mainDisplay=goggleViewerDisplay(obj, obj.overviewDSS, obj.hMainImgAx);
            obj.mainDisplay.drawNewZ();
            adjustContrast([], [], obj);
            axis(obj.hMainImgAx, 'equal')
            
            %% Info boxes
            obj.addInfoPanel(goggleViewInfoPanel(obj, obj.hFig, [0.83 0.49 0.16 0.31], obj.mainDisplay));
            obj.addInfoPanel(gogglePreLoader(obj, [0.83 0.39 0.16 0.09]));
            obj.addInfoPanel(goggleReadQueueInfoPanel(obj.hFig, [0.83 0.29 0.16 0.09], obj.mainDisplay.zoomedViewManager));
            obj.addInfoPanel(goggleCacheInfoPanel(obj, [0.83 0.19 0.16 0.09]));
            if ~ispc %TODO: fix the memory functions on Windows. Until this happens we can't run this
                obj.addInfoPanel(goggleSystemMemoryUsageInfoPanel(obj.hFig, [0.83 0.03 0.16 0.15], obj.mainDisplay.zoomedViewManager));
            end
            %% Set fonts to something nice
            set(findall(gcf, '-property','FontName'), 'FontName', gbSetting('font.name'))
            
            %% Load and set icon 
            try
                load bc.mat
                obj.hFig.PointerShapeCData=bcIco;
            catch
                warning('Unable to load custom brightness/contrast icon')
            end
            %% Start parallel pool
            h=splashWindow('Starting Parallel Pool', 'goggleViewer');
            drawnow;
            G=gcp;
            G.IdleTimeout=inf;

            delete(h);
            %% Show the figure, we're done here!
            obj.hFig.Visible='on';
        end 
    end
    
    methods(Access=protected)
        
        %% ---Scrolling
        function formatKeyScrollAndAddToQueue(obj, eventdata)
            goggleDebugTimingInfo(0, 'GV: KeyScroll event fired',toc, 's')
            mods=eventdata.Modifier;
            if ~isempty(mods)&& any(~cellfun(@isempty, strfind(mods, 'shift')))
                p=gbSetting('navigation.scrollIncrement');p=p(1);
            else
                p=gbSetting('navigation.scrollIncrement');p=p(2);
            end
            switch eventdata.Key
                case 'leftarrow'
                    obj.keyScrollQueue(-p)
                case 'rightarrow'
                    obj.keyScrollQueue(+p);
            end
        end
        
        function keyScrollQueue(obj, dir)
            
            obj.numScrolls=obj.numScrolls+dir;
            pause(gbSetting('navigation.keyboardUpdatePeriod'))
            if obj.numScrolls~=0
                p=obj.numScrolls;
                obj.numScrolls=0;
                obj.executeScroll(p,'zAxisScroll')
            end
        end
        
        function executeScroll(obj, nScrolls, scrollAction)
            %nScroll - scalar defining how many wheel clicks the user has produced (signed)
            %scrollAction - string defining which action to take. 

            %Set focus to main axes after a scroll. The UI interaction works better this way.
            %i.e. you can pan without having click on the figure window.
            axes(obj.hMainImgAx); 
            
            switch scrollAction
            case 'zAxisScroll'
                stdout=obj.mainDisplay.seekZ(nScrolls);
                if stdout
                    for ii=obj.additionalDisplays
                        ii.seekZ(nScrolls);
                    end
                    obj.changeAxes;
                    notify(obj, 'Scrolled')
                else
                    goggleDebugTimingInfo(0, 'GV: Scroll did not cause an axis change',toc, 's')
                end
            case 'zoomScroll'
                zoomRate=gbSetting('navigation.zoomRate'); %to zoom out
                if nScrolls<0
                    zoomRate=1/zoomRate; %to zoom out
                end
                for ii=1:abs(nScrolls)
                    obj.executeZoom(zoomRate) 
                end
            end
        end 

        
        %% ---Panning
        function formatKeyPanAndAddToQueue(obj, eventdata)
            goggleDebugTimingInfo(0, 'GV: KeyPan event fired',toc, 's')
            mods=eventdata.Modifier;
            if ~isempty(mods)&& any(~cellfun(@isempty, strfind(mods, 'shift')))
                p=gbSetting('navigation.panIncrement'); p=p(1);
            else
                p=gbSetting('navigation.panIncrement');p=p(2);
            end
            switch eventdata.Key
                case 'w'
                    obj.keyPanQueue(0, +range(ylim(obj.hMainImgAx))/p)
                case 'a'
                    obj.keyPanQueue(+range(xlim(obj.hMainImgAx))/p, 0)
                case 's'
                    obj.keyPanQueue(0, -range(ylim(obj.hMainImgAx))/p)
                case 'd'
                    obj.keyPanQueue(-range(xlim(obj.hMainImgAx))/p, 0)
            end
        end
        
        function keyPanQueue(obj, xChange, yChange)
           
            obj.panxInt=obj.panxInt+xChange;
            obj.panyInt=obj.panyInt+yChange;
            pause(gbSetting('navigation.keyboardUpdatePeriod'))
            
            if obj.panxInt~=0 || obj.panyInt~=0
                xOut=obj.panxInt;
                yOut=obj.panyInt;
                obj.panxInt=0;
                obj.panyInt=0;
                obj.executePan(xOut,yOut)
            end
        end
        
        function executePan(obj, xMove,yMove)
            if gbSetting('navigation.panModeInvert')
                xMove=-xMove;
                yMove=-yMove;
            end
            
            [xMove, yMove]=obj.checkPanWithinLimits(xMove, yMove);
            movedFlag=0;
            
            if xMove~=0
                newLim=xlim(obj.hMainImgAx)+xMove;
                xlim(obj.hMainImgAx,newLim)
                arrayfun(@(thisAxis) xlim(thisAxis.axes,newLim), obj.additionalDisplays)
                movedFlag=1;
            end
            if yMove~=0
                newLim=ylim(obj.hMainImgAx)+yMove;
                ylim(obj.hMainImgAx,newLim)
                arrayfun(@(thisAxis) ylim(thisAxis.axes,newLim), obj.additionalDisplays)
                movedFlag=1;
            end
            
            if movedFlag
                obj.changeAxes;
                notify(obj, 'Panned')
            else
                goggleDebugTimingInfo(0, 'GV: Pan did not cause an axis change',toc, 's')
            end
        end
        
        function [xMove,yMove]=checkPanWithinLimits(obj, xMove,yMove)
            xl=xlim(obj.hMainImgAx);
            yl=ylim(obj.hMainImgAx);
            
            if xl(1) + xMove < 0
                xMove = -xl(1);
            end
            if yl(1) + yMove < 0
                yMove = -yl(1);
            end
            if xl(2) + xMove > obj.mainDisplay.imageXLimOriginalCoords(2)
                xMove=obj.mainDisplay.imageXLimOriginalCoords(2) - xl(2);
            end
            if yl(2) + yMove > obj.mainDisplay.imageYLimOriginalCoords(2)
                yMove=obj.mainDisplay.imageYLimOriginalCoords(2) - yl(2);
            end
        end
        
        %% --- Zooming
        function executeZoom(obj, zoomfactor)
            C = get (obj.hMainImgAx, 'CurrentPoint');
            zoom(obj.hMainImgAx,zoomfactor)
            for ii=obj.additionalDisplays
                zoom(ii.axes, zoomfactor);
            end
            obj.centreView(C);
            obj.changeAxes
            notify(obj, 'Zoomed')

        end
        function centreView(obj, pointToCenterUpon)
            xl=xlim(obj.hMainImgAx);
            yl=ylim(obj.hMainImgAx);
            x=pointToCenterUpon(1, 1);
            y=pointToCenterUpon(2, 2);
            
            %% Calculate move
            centrePointX=mean(xl);
            centrePointY=mean(yl);
            
            xMove=round(x-centrePointX);
            yMove=round(y-centrePointY);
            %% Check move is within limits
            [xMove, yMove]=checkPanWithinLimits(obj, xMove, yMove);
            %% Do the move
            xlim(obj.hMainImgAx, xl+xMove);
            ylim(obj.hMainImgAx, yl+yMove);
            for ii=obj.additionalDisplays
                xlim(ii.axes, xl+xMove);
                ylim(ii.axes, yl+yMove);
            end
        end
        
        %% ---Update axes
        function changeAxes(obj)
            goggleDebugTimingInfo(0, 'GV: Calling mainDisplay updateZoomedView...',toc, 's')
            obj.mainDisplay.updateZoomedView
            goggleDebugTimingInfo(0, 'GV: mainDisplay updateZoomedView complete',toc, 's')
            for ii=obj.additionalDisplays
                goggleDebugTimingInfo(0, 'GV: Calling additional display updateZoomedView...',toc, 's')
                ii.updateZoomedView
                goggleDebugTimingInfo(0, 'GV: additional display updateZoomedView complete',toc, 's')
            end
            goggleDebugTimingInfo(0, 'GV: Firing ViewChanged Event',toc, 's')
            notify(obj, 'ViewChanged')
        end
        
        %% Info Panel Functions
        function addInfoPanel(obj, hPanel)
            if isempty(obj.infoPanels)
                obj.infoPanels={hPanel};
            else
                obj.infoPanels{end+1}=hPanel;
            end
        end
        
        function deleteInfoPanel(obj, hPanel)
            if ischar(hPanel)&&strcmp(hPanel, 'all')
                obj.deleteInfoPanel(1:numel(obj.infoPanels))
            else
                if isobject(hPanel)&&isscalar(hPanel)
                    idx=ismember(obj.infoPanels, hPanel);
                elseif isnumeric(hPanel)&&isvector(hPanel)
                   idx= hPanel;
                else
                    error('Unrecognised deleted panel specification')
                end
                for ii=1:numel(idx)
                    delete(obj.infoPanels{idx(ii)})
                end
                obj.infoPanels(idx)=[];
            end
        end
    end  %methods(Access=protected)
    
    methods 
        % Keep track of open plugins that want the viewer to cancel close requests
        function registerOpenPluginForCloseReqs(obj, plg)
            if isempty(obj.getCloseReqRegistrationIndexOfPlugin(plg))
                obj.openPluginsOverridingCloseReq{end+1}=plg;
            end
        end
        function deregisterOpenPluginForCloseReqs(obj, plg)
            plgIdx=obj.getCloseReqRegistrationIndexOfPlugin(plg);
            if ~isempty(plgIdx)
                obj.openPluginsOverridingCloseReq(plgIdx)=[];
            end
        end
        function idx=getCloseReqRegistrationIndexOfPlugin(obj, plg)
            idx=cellfun(@(x) eq(plg, x), obj.openPluginsOverridingCloseReq);
        end
    end
    
    methods % Destructor
        function delete(obj)
            notify(obj, 'ViewerClosing')
            delete(obj.overviewDSS)
            deleteInfoPanel(obj, 'all')
            delete(timerfind);
            if ishandle(obj.hFig)
                gbSetting('viewer.mainFigurePosition', obj.hFig.Position)
                delete(obj.hFig);
            end
        end
    end
end

function startDebugOutput
tic
clc
end    

%% Callbacks
function hFigMain_KeyPress (~, eventdata, obj)

    startDebugOutput

    %% What shall we do?
    ctrlMod=ismember('control', eventdata.Modifier);
    shiftMod=ismember('shift', eventdata.Modifier);
    if ~ctrlMod
        switch eventdata.Key
            case 'uparrow'
                obj.executeZoom(gbSetting('navigation.zoomRate'))
            case 'downarrow'
                obj.executeZoom(1/gbSetting('navigation.zoomRate'))
            case {'leftarrow', 'rightarrow'}
                obj.formatKeyScrollAndAddToQueue(eventdata);
            case {'w' 'a' 's' 'd'}
                obj.formatKeyPanAndAddToQueue(eventdata);
            case 'c'
                updateContrastHistogram(obj.mainDisplay, obj.hAxContrastHist)
           
            otherwise
                notify(obj, 'KeyPress', KeyPressEventData(eventdata))
        end
    else
        notify(obj, 'KeyPress', KeyPressEventData(eventdata))
    end
    if shiftMod
         if ~obj.contrastMode
             obj.contrastMode=1;
             obj.hFig.Pointer='custom';
         end
    end
        
end
function hFigMain_KeyRelease(~, eventdata, obj)
shiftMod=ismember('shift', eventdata.Modifier);
    if ~shiftMod
            if obj.contrastMode
                obj.contrastMode=0;
                obj.hFig.Pointer='arrow';
            end
    end
end
function hFigMain_BtnDown(~, ~, obj)
    if obj.contrastMode;
        obj.dragOrigin=mouseMove([],[],obj);
    end
end
function hFigMain_BtnUp(~, ~, obj)
    obj.dragOrigin=NaN;
end

function pos=mouseMove (~, ~, obj)
    C = get (obj.hMainImgAx, 'CurrentPoint');
    xl=xlim(obj.hMainImgAx);
    yl=ylim(obj.hMainImgAx);
    x=C(1, 1);
    y=C(2, 2);
    if x>=xl(1) && x<=xl(2) && y>=yl(1) && y<=yl(2)
        v=getPixelValueAtCoordinate(obj, x, y);
        notify(obj, 'CursorPositionChangedWithinImageAxes', CursorPositionData(C, v));
    else
        notify(obj, 'CursorPositionChangedOutsideImageAxes')
    end 
    
    pos=[x,y];
    
    if obj.contrastMode && ~any(isnan(obj.dragOrigin))
        %% Contrast
        delta=pos-obj.dragOrigin;
        delta(1)=delta(1)/range(xlim); % make it relative
        delta(2)=delta(2)/range(ylim);
        
        m=obj.hjSliderContrast.getLowValue();
        rng=obj.hjSliderContrast.getHighValue-m;
        newVal=obj.hjSliderContrast.getHighValue()+delta(2)*rng; % scales quite nicely
        
        if newVal>m
            obj.hjSliderContrast.setHighValue(newVal);
        else
            obj.hjSliderContrast.setHighValue(m+0);
        end
        
        
        %% Brightness
        bAdj=delta(1)*(obj.hjSliderContrast.maximum-obj.hjSliderContrast.minimum);
        
        newLow=obj.hjSliderContrast.getLowValue()+bAdj;
        newHigh=obj.hjSliderContrast.getHighValue()+bAdj;
        
        if newLow<obj.hjSliderContrast.minimum
            newHigh=newHigh+obj.hjSliderContrast.minimum-newLow-1;
            newLow=obj.hjSliderContrast.minimum;
        end
        
        if newHigh>obj.hjSliderContrast.maximum
            newLow=newLow+obj.hjSliderContrast.maximum-newHigh-1;
            newHigh=obj.hjSliderContrast.maximum;
        end
        
        obj.hjSliderContrast.setHighValue(newHigh);
        obj.hjSliderContrast.setLowValue(newLow);
        
        %% Reset
        obj.dragOrigin=pos;
    end
    
    
    
end
function hFigMain_ScrollWheel(~, eventdata, obj)
    startDebugOutput

    goggleDebugTimingInfo(0, 'GV: WheelScroll event fired',toc, 's')
    
    modifiers = get(obj.hFig,'currentModifier');          
    %If user ctrl-scrolls we zoom instead of change z-level
    if ismember('control',modifiers)    
        obj.executeScroll(eventdata.VerticalScrollCount,'zoomScroll');    
        return
    end

    p=gbSetting('navigation.scrollIncrement');
    if ismember('shift',modifiers);
        p=p(1);
    else
        p=p(2);
    end
    obj.executeScroll(p*eventdata.VerticalScrollCount,'zAxisScroll'); %scroll through z-stack

end
function adjustContrast(~, ~, obj)
%     if nargin<1
%         hContrastLim=[];
%     end
%     if ~isempty(hContrastLim)&&~all(isstrprop(hContrastLim.String, 'digit')) %it's invalid, use the previous value
%         if hContrastLim==obj.hAxContrastMin
%             hContrastLim.String=obj.mainDisplay.contrastLims(1);
%         elseif hContrastLim==obj.hAxContrastMax
%             hContrastLim.String=obj.mainDisplay.contrastLims(2);
%         end
%     else
%         obj.mainDisplay.contrastLims=[str2double(obj.hAxContrastMin.String) str2double(obj.hAxContrastMax.String)];
%     end
obj.mainDisplay.contrastLims=[obj.hjSliderContrast.getLowValue(), obj.hjSliderContrast.getHighValue()];
end
function closeRequest(~,~,obj)
if isempty(obj.openPluginsOverridingCloseReq)
    delete(obj)
else
    msgbox('One or more plugins are open that require your attention before closing')
end
end
function changeProcessingSteps(~, ~, obj)
    zvm=obj.mainDisplay.zoomedViewManager;
    newPipeline=setImageProcessingPipeline(zvm.imageProcessingPipeline);
    zvm.imageProcessingPipeline=newPipeline;
    zvm.clearCache;
end
function handleMouseClick(~,~, obj)
    notify(obj, 'ViewClicked');
end

function adjustXYPosClick(caller,~,obj)
    zvm=obj.mainDisplay.zoomedViewManager;
    if isempty(zvm.xyPositionAdjustProfile)
        zProfile=loadXYAlignmentProfile;
        if ~isempty(zProfile)
            zvm.xyPositionAdjustProfile=zProfile;
            caller.Checked='on';
            zvm.clearCache;
        end
    else
        caller.Checked='off';
        zvm.xyPositionAdjustProfile=[];
        zvm.clearCache;
    end
end

%% Utilities
function updateContrastHistogram(dsStack,hContrastHist_Axes)
data=dsStack.hImg.CData;
n=hist(double(data(:)), numel(data)/100);n=n/max(n);
bar(linspace(0, 1, length(n)), n, 'Parent', hContrastHist_Axes, 'FaceColor', [0.8 0.8 0.8])
hContrastHist_Axes.Color=[0.1 0.1 0.1];
hold(hContrastHist_Axes, 'on')

% Overlay fake axes
line([0 0], [-0.08 1.1], 'Color', [0.8 0.8 0.8],'Parent', hContrastHist_Axes) %y axis
line([-0.05 0.01], [1 1],  'Color', [0.8 0.8 0.8],'Parent', hContrastHist_Axes) %top y axis tick
line([1 1], [-0.08 0.001], 'Color', [0.8 0.8 0.8],'Parent', hContrastHist_Axes) %end x tick
%        rectangles cover any funny error pixels
rectangle('Position', [-0.08 1 2 1], 'FaceColor',[0.1 0.1 0.1], 'EdgeColor', 'none','Parent', hContrastHist_Axes)
rectangle('Position', [-1.001 -1.001 1 1], 'FaceColor', [0.1 0.1 0.1], 'EdgeColor', 'none','Parent', hContrastHist_Axes)
rectangle('Position', [1.01 -1.001 1 1], 'FaceColor', [0.1 0.1 0.1],'EdgeColor', 'none','Parent', hContrastHist_Axes)

% Ovelay limit lines
%        line(ones(2, 1)*contrastMin, [-0.05 1], 'Parent', hContrastHist_Axes)
%        line(ones(2, 1)*contrastMax, [-0.05 1], 'Parent', hContrastHist_Axes)
hold(hContrastHist_Axes, 'off')
set(hContrastHist_Axes, 'XTick', [], 'XColor', get(0, 'defaultuicontrolbackgroundcolor'))
set(hContrastHist_Axes, 'YTick', [], 'YColor', get(0, 'defaultuicontrolbackgroundcolor'))
xlim(hContrastHist_Axes, [-0.05 1.1])
ylim(hContrastHist_Axes, [-0.1 1.1])
end

function exportViewToWorkspace(~,~,obj)
    if obj.mainDisplay.zoomedViewManager.imageVisible;
        I=obj.mainDisplay.zoomedViewManager.currentImageViewData;
    else
        I=obj.mainDisplay.currentImageViewData;
    end
    xView=round(obj.hMainImgAx.XLim);xView(xView<1)=1;
    yView=round(obj.hMainImgAx.YLim);yView(yView<1)=1;
    proposedImageName=sprintf('%s_%s_x%u_%u_y%u_%u_layer%04u',...
        obj.overviewDSS.experimentName, ...
        obj.overviewDSS.channel, ...
        xView(1), xView(2), ...
        yView(1), yView(2), ...
        obj.mainDisplay.currentZPlaneOriginalLayerID);
    
    retry=1;
    while retry
        imageName=inputdlg('Image variable name:', 'Export Image to Base Workspace', 1, {proposedImageName});
       
        if isempty(imageName)
            return
        else
            imageName=imageName{1};
        end
            varExistsInBase=evalin('base', sprintf('exist(''%s'', ''var'');', imageName));
            if varExistsInBase
                if ~strcmp(questdlg(sprintf('A variable of name\n%s\n already exists. Overwrite?', imageName), ...
                               'Export Image to Base Workspace', 'Yes', 'No', 'No'), 'Yes')
                    continue
                end
            end
            assignin('base',  matlab.lang.makeValidName(imageName), I);
            retry=0;
    end
end

function zProfile=loadXYAlignmentProfile
    [f,p]=uigetfile({'*.zpfl', 'Z-Profile (*.zpfl)'; '*.csv', 'CSV-File (*.csv)'; '*.*', 'All Files (*.*)'}, 'Select Z Profile To Register To', gbSetting('defaultDirectory'));
    pathToCSVFile=fullfile(p,f);
    if exist(pathToCSVFile, 'file')
        zProfile=dlmread(pathToCSVFile);
    else
        zProfile=[];
    end
end

function v=getPixelValueAtCoordinate(obj, x, y)
zoomedViewStatus=obj.mainDisplay.zoomedViewNeeded&&obj.mainDisplay.zoomedViewManager.currentSliceFileExistsOnDisk;
if zoomedViewStatus
    [~, xIdx]=min(abs(x-obj.mainDisplay.zoomedViewManager.hImg.XData));
    [~, yIdx]=min(abs(y-obj.mainDisplay.zoomedViewManager.hImg.YData));
    v=obj.mainDisplay.zoomedViewManager.hImg.CData(yIdx, xIdx);
else
    [~, xIdx]=min(abs(x-obj.mainDisplay.overviewStack.xCoordsVoxels));
    [~, yIdx]=min(abs(y-obj.mainDisplay.overviewStack.yCoordsVoxels));
    v=obj.mainDisplay.hImg.CData(yIdx, xIdx);
end
end

%% Plugins menu creation
function addPlugins(hMenuBase, obj, pluginsDirName, separateFirstEntry)
    if nargin<4||isempty(separateFirstEntry)
        separateFirstEntry=0;
    end
    pluginsDir=fullfile(fileparts(which('goggleViewer')), pluginsDirName);
    
    if ~exist(pluginsDir, 'dir')
        error('plugins directory not found')
    else
        fprintf('Adding plugins in directory %s to menu\n',pluginsDirName)
        
    end
    
    filesInPluginsDirectory=dir(fullfile(pluginsDir, '*.m'));
    
    for ii=1:numel(filesInPluginsDirectory)
        if isValidGoggleBoxPlugin(pluginsDir, filesInPluginsDirectory(ii).name)
            
            [pluginDisplayString, pluginStartCallback]=getPluginInfo(filesInPluginsDirectory(ii));
                       
            hItem=uimenu(hMenuBase, 'Label', pluginDisplayString, 'Callback', pluginStartCallback, 'UserData', obj);
            if separateFirstEntry&&ii==1
                hItem.Separator='on';
            end
        end
    end
end


function isGBPlugin=isValidGoggleBoxPlugin(pluginsDir, pluginsFile)
    fName=fullfile(pluginsDir, pluginsFile);
    if isdir(fName)
        isGBPlugin=0;
    else
        f=fopen(fullfile(pluginsDir, pluginsFile));
        codeStr=fread(f, Inf, '*char')';
        hasGBPAsSuperClass=~isempty(strfind(codeStr, '<goggleBoxPlugin'));
        if hasGBPAsSuperClass
            isGBPlugin=~isAbstractCode(codeStr);
        else
            isGBPlugin=0;
        end
        fclose(f);
    end
end

function abstractPluginFlag=isAbstractCode(codeStr)
   
    abstractPluginFlag=strfind(lower(codeStr), 'abstract');
    if isempty(abstractPluginFlag)
        abstractPluginFlag=0;
    else
        abstractPluginFlag=1;
    end
   
end

function [pluginDisplayString, pluginStartCallback]=getPluginInfo(pluginFile)
pluginDisplayString=eval(strrep(pluginFile.name, '.m', '.displayString;'));
pluginStartCallback={eval(['@', strrep(pluginFile.name, '.m', '')])};
end















