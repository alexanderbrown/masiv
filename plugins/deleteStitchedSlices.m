classdef  deleteStitchedSlices<goggleBoxPlugin
%DELETESTITCHEDSLICES Summary of this function goes here
%   Detailed explanation goes here

properties
    
end
methods
    function obj=deleteStitchedSlices(caller, ~, channels, slices)
        obj=obj@goggleBoxPlugin(caller);
        %% Parse input
        if isa(caller, 'TVStitchedMosaicInfo')
            mosaicInfo=caller;
        elseif isa(caller, 'matlab.ui.container.Menu')
            gvObj=caller.UserData;
            mosaicInfo=gvObj.mosaicInfo;
        else
            error('Unrecognised parameter. First argument should either be a TVStitchedMosaicInfo object, or a plugins menu objext')
        end
        if nargin<4
            slices=[];
        end
        if nargin<3
            channels={};
        end
        if ~isempty(channels)&&ischar(channels)
            channels={channels};
        end
        %% Show GUI if any specifications not provided
        if isempty(channels)||isempty(slices)
            [channels, slices]=getSlicesForDeletion(mosaicInfo, channels, slices);
            if isempty(channels)||isempty(slices)
                deleteRequest(obj)
                return
            end
            filesToDelete=getFilesToDelete(mosaicInfo, channels, slices);
            goAhead=showFileListToDelete(filesToDelete);
            if goAhead
                doDelete(mosaicInfo, filesToDelete)
                
            else
                goggleDebugTimingInfo(0, 'File Deletion Cancelled')
            end
            deleteRequest(obj)
        end
       
    end
    function deleteRequest(obj)
        deleteRequest@goggleBoxPlugin(obj);
    end
end
methods(Static)
    function f=displayString()
         f='Delete Stitched Slices...';
    end
end

end

function [channels, slices]=getSlicesForDeletion(mosaicInfo, channels, slices)
    %% Params
    fontSz=12;
    mainFont='Titillium';
    initialChannelSelection={'Ch01', 'Ch03'};
    %% Declarations: Main
    hFig=dialog(...
        'Name', sprintf('Delete full-resolution stitched images... %s',mosaicInfo.experimentName), ...
        'ButtonDownFcn', '', 'CloseRequestFcn', @cancelButtonClick);
     hOKButton=uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.8 0.02 0.18 0.08], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style', 'pushbutton', ...
        'String', 'OK', ...
        'Callback', 'uiresume(gcbf)');
    hCancelButton=uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.6 0.02 0.18 0.08], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style', 'pushbutton', ...
        'String', 'Cancel', ...
        'Callback', @cancelButtonClick); %#ok<NASGU>
        
    %% Declarations: channels
    if isempty(channels)
        channels=initialChannelSelection;
    end
    hChannels=uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.02 0.12 0.2 0.86], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style', 'listbox', ...
        'Max', 10, 'Min', 2, ...
        'Value', find(ismember(fieldnames(mosaicInfo.stitchedImagePaths), channels)),...
        'String', fieldnames(mosaicInfo.stitchedImagePaths), ...
        'Callback', @selectedChannelChanged);
    
    %% Declarations: slices
    if isempty(slices)
        
        slcMax=numel(mosaicInfo.stitchedImagePaths.(channels{1}));
        slcMin=1;
        inc=1;
    else
        slcMax=max(slices);
        slcMin=min(slices);
        inc=diff(slices);
    end
        
    
    uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.24 0.77 0.2 0.07], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style', 'text', ...
        'String', 'From:', ...
        'HorizontalAlignment', 'right');
     uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.24 0.67 0.2 0.07], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style', 'text', ...
        'String', 'Increment:', ...
        'HorizontalAlignment', 'right');
     uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.24 0.57 0.2 0.07], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style', 'text', ...
        'String', 'To:', ...
        'HorizontalAlignment', 'right');
    uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.24 0.45 0.66 0.07], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style','text' , ...
        'String', 'All indices are 1-based; From and To are inclusive!', ...
        'HorizontalAlignment', 'center');
    
     hSliceFromFP=uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.71 0.77 0.2 0.07], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style', 'text', ...
        'HorizontalAlignment', 'left');
    hSliceToFP=uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.71 0.57 0.2 0.07], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style', 'text', ...
        'HorizontalAlignment', 'left');
    
    hSliceFrom=uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.5 0.79 0.2 0.07], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style', 'edit', ...
        'Callback', {@showMatchingFilePath, hSliceFromFP}, ...
        'String', num2str(slcMin));
    hSliceIncrement=uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.5 0.69 0.2 0.07], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style', 'edit', ...
        'String', num2str(inc));
    hSliceTo=uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.5 0.59 0.2 0.07], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style', 'edit', ...
        'Callback', {@showMatchingFilePath, hSliceToFP}, ...
        'String', num2str(slcMax));
    
    %% Main execution: wait for OK or cancel
    
    showMatchingFilePath(hSliceFrom, [], hSliceFromFP);
    showMatchingFilePath(hSliceTo, [], hSliceToFP);

    
    uiwait(hFig);
    delete(hFig)
    %% Callbacks
    function cancelButtonClick(~,~)
        slices=[];
        channels={};
        uiresume(gcbf)
    end
    function selectedChannelChanged(~,~)
        channels=hChannels.String(hChannels.Value);
    end
    function showMatchingFilePath(caller, ~, outputText)
        slcNum=str2double(caller.String)-1;
        if isnan(slcNum)
            outputText.String='INVALID SLICE NUMBER';
        else
            outputText.String=sprintf('Layer_%04u', slcNum);
        end
        if isempty(str2double(hSliceFrom.String))||isempty(str2double(hSliceTo.String))||isempty(str2double(hSliceIncrement.String))||...
            isnan(str2double(hSliceFrom.String))||isnan(str2double(hSliceTo.String))||isnan(str2double(hSliceIncrement.String))
            hOKButton.Enable='off';
        else
            slices=str2double(hSliceFrom.String):str2double(hSliceIncrement.String):str2double(hSliceTo.String);
            hOKButton.Enable='on';
        end
    end
end

function goAhead=showFileListToDelete(filesToDelete)
     %% Params
    fontSz=12;
    mainFont='Titillium';
    %% Declarations: Main
    hFig=dialog(...
        'Name','Confirm Stitched Image Deletion', ...
        'ButtonDownFcn', '', 'CloseRequestFcn', @cancelButtonClick);
     hOKButton=uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.8 0.02 0.18 0.08], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style', 'pushbutton', ...
        'String', 'OK', ...
        'Callback', @OKButtonClick); %#ok<NASGU>
    hCancelButton=uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.6 0.02 0.18 0.08], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style', 'pushbutton', ...
        'String', 'Cancel', ...
        'Callback', @cancelButtonClick);  %#ok<NASGU>
    %% List of files to delete
    hListOfFiles=uicontrol(...
        'Parent', hFig, ...
        'Units', 'normalized', ...
        'Position', [0.02 0.12 0.96 0.86], ...
        'FontName', mainFont, ...
        'FontSize', fontSz, ...
        'Style', 'edit', ...
        'Max', 10, 'Min', 1, ...
        'String', sprintf('%s\n', filesToDelete{:})); %#ok<NASGU>
    %% Main execution: wait for OK or cancel
    
    goAhead=[];
    uiwait(hFig);
    delete(hFig)
    %% Callbacks
    function cancelButtonClick(~,~)
        goAhead=0;
        uiresume(gcbf)
    end
    function OKButtonClick(~,~)
        button=questdlg(sprintf('Are you sure you want to delete these %u files? \nThis CANNOT be undone!', numel(filesToDelete)), ...
            'Be very sure of this!', 'OK', 'Cancel', 'Cancel'); 
        if strcmp(button, 'OK')
            goAhead=1;    
            uiresume(gcbf)
        end 
    end
end
function filesToDelete= getFilesToDelete(mosaicInfo, channels, slices)

filesToDelete={};
for ii=1:numel(channels)
    allFilesThisChannel=mosaicInfo.stitchedImagePaths.(channels{ii});
    filesToDeleteThisChannel=allFilesThisChannel(slices);
    
    doesTheFileActuallyExist=logical(cellfun(@(x) exist(x, 'file'), fullfile(mosaicInfo.baseDirectory, filesToDeleteThisChannel)));
    
    existingFilesToDeleteThisChannel=filesToDeleteThisChannel(doesTheFileActuallyExist);
    filesToDelete=[filesToDelete; existingFilesToDeleteThisChannel]; %#ok<AGROW>
end
filesToDelete=sort(filesToDelete);
end

function doDelete(mosaicInfo, filesToDelete)
goggleDebugTimingInfo(0, 'Deleting Files:')
                swb=SuperWaitBar(numel(filesToDelete), 'Deleting Files');
                for ii=1:numel(filesToDelete)
                    fullFilePath=fullfile(mosaicInfo.baseDirectory, filesToDelete{ii});
                    delete(fullFilePath)
                    goggleDebugTimingInfo(1, fullFilePath)
                    swb.progress;
                end
                delete(swb)
                clear swb
end