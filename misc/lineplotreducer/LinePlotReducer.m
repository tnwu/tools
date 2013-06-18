classdef LinePlotReducer < handle
    
% LinePlotReducer
%
% Manages the information in a standard MATLAB plot so that only the
% necessary number of data points are shown. For instance, if the width of
% the axis in the plot is only 500 pixels, there's no reason to have more
% than 1000 data points along the width. This tool selects which data
% points to show so that, for each pixel, all of the data mapping to that
% pixel is crushed down to just two points, a minimum and a maximum. Since
% all of the data is between the minimum and maximum, the user will not see
% any difference in the reduced plot compared to the full plot. Further, as
% the user zooms in or changes the figure size, this tool will create a new
% map of reduced points for the new axes limits automatically (it requires
% no further user input).
% 
% Using this tool, users can plot huge amounts of data without their 
% machines becoming unresponsive, and yet they will still "see" all of the 
% data that they would if they had plotted every single point.
%
% To keep things simple, the interface allows a user to pass in arguments
% in the same way those arguments would be passed directly to most line
% plot commands. For instance:
%
% plot(t, x);
%
% Becomes:
%
% LinePlotReducer(t, x);
%
% More arguments work as well.
%
% plot(t, x, 'r:', t, y, 'b', 'LineWidth', 3);
%
% Becomes:
%
% LinePlotReducer(t, x, 'r:', t, y, 'b', 'LineWidth', 3);
%
% Note that LinePlotReducer returns a LinePlotReducer object as output.
%
% lpr = LinePlotReducer(t, x);
%
% Another function, reduce_plot, takes exactly the same arguments as
% LinePlotReducer, but returns the plot handles instead of a
% LinePlotReducer object.
%
% h_plots = reduce_plot(t, x);
%
% One can use reduce_plot or LinePlotReducer according to one's comfort
% with using objects in MATLAB. By using reduce_plot, one does not need to
% use objects if one doesn't want to.
%
% The plot handles are also available as a public property of
% LinePlotReducer called h_plot. These handles would allow one to, e.g.,
% change a line color or marker.
%
% By default 'plot' is the function used to display the data, however,
% other functions can be used as well. For instance, to use 'stairs':
%
% LinePlotReducer(@stairs, t, x);
%
% Alternately, if one already has an existing plot, but wants a
% LinePlotReducer to manage it, one can simply pass the plot handles to a
% new LinePlotReducer, such as:
%
% h = plot(t, x, 'r:');
% LinePlotReducer(h);
%
% Finally, one can also set up a plot with a "small" set of data, then pass
% the plot handle and full x and y data to LinePlotReducer. This allows a
% user to create a detailed custom plot, but still use the LinePlotReducer
% without ever having to plot all of the data. For instance:
%
% h = plot(t([1 end]), x([1 end]), 'rd--', t([1 end]), y([1 end]), 'bs');
% LinePlotReducer(h, t, x, t, y);
%
% One can still use normal zooming and panning tools, whether in the figure
% window or from the command line, and the LinePlotReducer will still
% notice that the axes limits or size are changing and will automatically
% create a new, reduced data set to fit the current size.
%
% LinePlotReducer looks best on continuous lines. When plotting points
% only (with no connecting line), it might be noticeable that only the 
% minimum and maximum are showing up in a plot. A user can still explore
% the data quickly, and details will always be filled in when the user
% zooms (all the way down to the raw data).
%
% Finally, for those who need to zoom and pan frequently, a utility is
% included to make this a little faster. When a LinePlotExplorer is applied
% to a figure, it allows the user to zoom in and out with the scroll wheel
% and pan by clicking and dragging. Left and right bounds can also be
% passed to LinePlotExplorer.
%
% lpe = LinePlotExplorer(gcf(), 0, 5);
%
% The LinePlotExplorer is not strictly related to the LinePlotReducer.
% However, frequent zooming and handling large data so frequently occur at
% the same time that this class was included for convenience.
%
% Tucker McClure
% Copyright 2013, The MathWorks, Inc.

    properties
        
        % Handles
        h_figure;
        h_axes;
        h_plot;
        
        % Original data
        x;
        y;
        y_to_x_map;
        
        % Extrema
        x_min;
        x_max;
        
        % Status
        busy = false;
        
    end
    
    methods
        
        % Create a ReductiveViewer for the x and y variables.
        function o = LinePlotReducer(varargin)
            
            % We're busy. Ignore resizing and things.
            o.busy = true;

            % If the user is just passing in an array of plot handles,
            % we'll take over managing the data shown in the plot.
            taking_over_existing_plot =    nargin >= 1 ...
                                        && isvector(varargin{1}) ...
                                        && all(ishandle(varargin{1}));
            if taking_over_existing_plot

                % Record the handles.
                o.h_plot   = varargin{1};
                o.h_axes   = get(o.h_plot(1), 'Parent');
                o.h_figure = get(o.h_axes,    'Parent');
                 
                % Get the original data either from the plot or from input
                % arguments.
                if nargin == 1
                    
                    o.x = get(o.h_plot, 'XData');
                    o.y = get(o.h_plot, 'YData');
                    o.y_to_x_map = 1:size(o.y, 1);
                    
                    for k = 1:length(o.x)
                        o.x{k} = o.x{k}(:);
                        o.y{k} = o.y{k}(:);
                    end
                    
                end
                
                start = 2;
                axes_specified = false;
                
            % Otherwise, we need to plot the data.
            else
                
                % The first argument might be a function handle or it might
                % just be the start of the data. 'next' will represent the
                % index we need to examine next.
                start = 1;

                % If the first input is a function handle, use it to plot.
                % Otherwise, use the normal @plot function.
                if isa(varargin{start}, 'function_handle')
                    plot_fcn = varargin{1};
                    start = start + 1;
                else
                    plot_fcn = @plot;
                end

                % Check for an axes input.
                if    isscalar(varargin{start}) ...
                   && ishandle(varargin{start}) ...
                   && strcmp(get(varargin{start}, 'Type'), 'axes')
                
                    % User provided the axes. Keep 'em.
                    o.h_axes = varargin{start};
                    
                    % Get the figure.
                    o.h_figure = get(o.h_axes, 'Parent');
                    
                    % Make them active.
                    set(0, 'CurrentFigure', o.h_figure);
                    set(o.h_figure, 'CurrentAxes', o.h_axes);
                    
                    % Move the start.
                    start = start + 1;
                    
                    axes_specified = true;
                    
                else
                    
                    % Record the handles.
                    o.h_figure   = gcf();
                    o.h_axes     = gca();
                    
                    axes_specified = false;
                    
                end
                
            end

            % Function to check if something's a line spec
            is_line_spec = @(s)    ischar(s) ...
                && isempty(regexp(s, '[^rgbcmykw\-\:\.\+o\*xsd\^v\>\<ph]', 'once'));

            % A place to store the linespecs as we find them.
            linespecs = {};

            % Loop through all of the inputs.
            km1_was_x = false;
            ym = [];
            for k = start:nargin+1

                % If it's a bunch of numbers...
                if k <= nargin && isnumeric(varargin{k})

                    % If we already have an x, then this must be y.
                    if km1_was_x

                        % Rename for simplicity.
                        ym = varargin{k};
                        xm = varargin{k-1};

                        % Transpose if necessary.
                        if    size(xm, 1) == 1 ...
                           && size(xm, 2) == size(ym, 2)
                            xm = xm';
                            ym = ym';
                        end

                        % Store y, x, and a map from y index to x
                        % index.
                        for c = 1:size(ym, 2)
                            if c <= size(xm, 2)
                                o.x{end+1} = xm(:, c);
                            end
                            o.y{end+1} = ym(:, c);
                            o.y_to_x_map(end+1) = length(o.x);
                        end

                        % We've now matched this x.
                        km1_was_x = false;

                    % If we don't have an x, this must be x.
                    else
                        km1_was_x = true;
                    end

                % It's not numeric.
                else

                    % If we had an x and were looking for a y, it
                    % probably was actually a y with an implied x.
                    if km1_was_x

                        % Rename for simplicity.
                        ym = varargin{k-1};
                        o.x{end+1} = (1:size(ym, 1))';

                        % Store y, x, and a map from y index to x
                        % index.
                        for c = 1:size(ym, 2)
                            o.y{end+1} = ym(:, c);
                            o.y_to_x_map(end+1) = length(o.x);
                        end

                    end

                    % Maybe a line spec?
                    if k <= nargin && is_line_spec(varargin{k})

                        linespecs(length(o.y)+1 - (1:size(ym, 2))) =...
                            varargin(k); %#ok<AGROW>

                    % If it's neither numbers nor a line spec, stop.
                    else
                        break;
                    end

                end

            end

            % We've now parsed up to k.
            start = k;

            % Create cell arrays for the reduced data.
            x_r = cell(1, length(o.y));
            y_r = cell(1, length(o.y));

            % Get the axes width once.
            width = get_axes_width(o.h_axes);

            % Reduce the data!
            for k = 1:length(o.y)
                [x_r{k}, y_r{k}] = reduce_to_width(...
                    o.x{o.y_to_x_map(k)}(:), ...
                    o.y{k}(:), ...
                    width, ...
                    [-inf inf]);
            end

            % If taking over a plot, just update it. Otherwise, plot it.
            if taking_over_existing_plot
                o.RefreshData();
                
            % Otherwise, we need to make a new plot.
            else
                
                % Make the plot arguments.
                plot_args = {};
                
                % Add the axes handle if the user supplied it.
                if axes_specified
                    plot_args{end+1} = o.h_axes;
                end
                
                % Add the lines.
                for k = 1:length(o.y)
                    plot_args{end+1} = x_r{k}; %#ok<AGROW>
                    plot_args{end+1} = y_r{k}; %#ok<AGROW>
                    if k < length(linespecs) && ~isempty(linespecs{k})
                        plot_args{end+1} = linespecs{k}; %#ok<AGROW>
                    end
                end
                
                % Add any other arguments.
                plot_args = [plot_args, varargin(start:end)];
                
                % Plot it!
                try
                    
                    % plotyy
                    if isequal(plot_fcn, @plotyy)
                        
                        [o.h_axes, h1, h2] = plot_fcn(plot_args{:});
                        o.h_plot = [h1 h2];
                        
                    % stairs
                    elseif isequal(plot_fcn, @stairs) && length(o.y) > 1
                        
                        error(['Function ''stairs'' cannot plot ' ...
                               'multiple lines at once using ' ...
                               'LinePlotReducer. Try using ''hold on'' '...
                               'and calling LinePlotReducer once for ' ...
                               'each line.']);
                           
                    % All other lineseries functions.
                    else
                        o.h_plot = plot_fcn(plot_args{:});
                    end
                    
                catch err
                    fprintf(['LinePlotReducer had trouble managing the '...
                             '%s function. Perhaps the arguments are ' ...
                             'incorrect. The error is below.\n'], ...
                            func2str(plot_fcn));
                    rethrow(err);
                end
                
            end
            
            % Listen for changes to the x limits of the axes.
            linkaxes(o.h_axes, 'x');
            for k = 1:length(o.h_axes)
                addlistener(o.h_axes(k), 'XLim',     'PostSet', ...
                            @(~, ~) o.Resize);
                addlistener(o.h_axes(k), 'Position', 'PostSet', ...
                            @(~, ~) o.Resize);
            end
            addlistener(o.h_figure, 'Position', 'PostSet', @(~,~)o.Resize);
            
            % Force the drawing to happen now.
            drawnow();

            % No longer busy.
            o.busy = false;
            
        end
                
    end
    
    methods
        
        % Redraw all of the data.
        function RefreshData(o)

            % We're busy now.
            o.busy = true;
            
            % Get the new limits. Sometimes there are multiple axes stacked
            % on top of each other. Just grab the first. This is really
            % just for plotyy.
            lims = get(o.h_axes(1), 'XLim');

            % Get the axes width once.
            width = get_axes_width(o.h_axes(1));
            
            % For all data we manage...
            for k = 1:length(o.h_plot)
                
                % Reduce the data.
                if iscell(o.x)
                    [x_r, y_r] = reduce_to_width(...
                                    o.x{o.y_to_x_map(k)}(:), ...
                                    o.y{k}(:), ...
                                    width, lims);
                else
                    c = min(k, size(o.x, 2)); % x can be n-by-1 or n-by-m.
                    [x_r, y_r] = reduce_data_to_axes(o.x(:,c), o.y(:,k),...
                                                     width, lims);
                end
                
                % Update the plot.
                set(o.h_plot(k), 'XData', x_r, 'YData', y_r);
                
            end

            % We're no longer busy.
            o.busy = false;
            
        end

        % If the user resizes the figure, we should update.
        function Resize(o, ~, ~)
            
            % If we're not already busy updating and if the plots still
            % exist.
            if ~o.busy && all(ishandle(o.h_plot))
                o.RefreshData();
            end
            
        end
        
    end
    
end
