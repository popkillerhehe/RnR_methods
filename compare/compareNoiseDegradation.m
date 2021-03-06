% this script runs the rank-order correlation and Radon integral replay methods
% on simulated data where replay events are systematically degraded, either
% by removed 'real' spikes, or adding spurious 'noise' spikes.
%
% Copyright (C) 2019 Adrien Peyrache & David Tingley.
%
% This program is free software; you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation; either version 2 of the License, or
% (at your option) any later version.


%% initial parameters to play with 
% visualize each simulation?
display = 0;
% # of place fields for simulations
numCells = 100; 
% number of spikes to add or remove will be multiplicative of noiseStep. Should not be greater than 50. (as up to 100 spikes are added)
% The smaller (minimum: 1) the longer the simulation.
noiseStep = 2; 
 % 15 ms bins for the Bayesian method
radonBinSize = 15;
% number of sims to run for each parameter set, 3-10 is usually a good range (smaller #s run faster)
numIterations = 2; 
% average FR for distribution of fields, measured in Hz;
inFieldMeanRate = 15; 

noiseBins = round(90/noiseStep)+1;
if noiseBins <2
    error('noiseStep is too small');
end
   
% pick one of the following 
% fieldRateDistro = ones(numCells,1) .* inFieldMeanRate; % everyone is equal
% fieldRateDistro = ones(numCells,1) .* normrnd(inFieldMeanRate,inFieldMeanRate./3,numCells,1); % gaussian distributed in-field rates
fieldRateDistro = ones(numCells,1) .* lognrnd(log(inFieldMeanRate),log(inFieldMeanRate)./3,numCells,1); % lognorm distributed in-field rates
fieldRateDistro(fieldRateDistro>120) = 120; % cap for lognorm distro


%% first, let's make some place fields.
offsets_rate = {round(sigmoid(1:100,50,.09) .* 100)... % reward/end over-representation
          1:100 ...                                    % linearly spaced PFs
          randi(100,1,100)};                           % randomly spaced PFs

for o = 1:length(offsets_rate)
    for cell = 1:numCells
        rateMaps{o}(cell,:) = minmax_norm(Smooth([zeros(1,offsets_rate{o}(cell)) 1 zeros(1,100-offsets_rate{o}(cell))]',5)) .* fieldRateDistro(cell); % this multiplier makes the in-field FR's about ~15Hz for each cell 
    end
end

%% ok, now let's make some ripple examples..
offsets_rip = {round([(numCells/2-logspace(2,0.8,50)./2)+3 (logspace(0.8,2,50)./2)+numCells/2-3])... % logarithmicaly spaced spikes to replicate population FR during ripples
               1:100}; % linearly spaced spikes within each ripple

%% we're going to iterate thru adding noise, and subtracting signal           
noise_rankOrd = nan(noiseBins,noiseBins,numIterations);
noise_integral = nan(noiseBins,noiseBins,numIterations);
noise_reactICA = nan(noiseBins,noiseBins,numIterations);
noise_reactPCA = nan(noiseBins,noiseBins,numIterations);

figure(1),clf
figure(2),clf
figure(3),clf
textInfo = [];

for nSub = 0:noiseBins-1 % subtract N 'real' spikes
   
    
    for nAdd = 0:noiseBins-1 % add N 'noise' spikes
         percent = 100*(nSub*(noiseBins-1)+nAdd)/noiseBins.^2;
    
        if ~isempty(textInfo)
            fprintf(repmat('\b',[1 length(textInfo)]))
        end
    
        textInfo = ['Percentage completed: ' num2str(round(percent)) '%'];
        fprintf('%s',textInfo)
    
        for o = 2        %% this can be varied [1-3] if you would like a different 'in-ripple' firing rate pattern (see lines 27-28)
            for oo = 2   %% this can be varied [1-3] if you would like a different PF tiling of space (see lines 12-21)
                for cell =1:numCells
                   rippleEvent{o}(cell,:) = ([zeros(1,offsets_rip{o}(cell)) 1 zeros(1,100-offsets_rip{o}(cell))]);
                end
                for iter = 1:numIterations 
                    spks = find(rippleEvent{o}==1);
                    rip = rippleEvent{o}; 
                    r = randperm(100);
                    rip(spks(r(1:nSub*noiseStep))) = 0;
                    r = randperm(length(rip(:)));
                    rip(r(1:nAdd*noiseStep)) = 1;
                    keep = find(sum(rip')>0); % used for rank order corr

                    %% discretize for radon integral here
                    for c = 1:size(rip,1)
                       rip_smooth(c,:) = rebin(rip(c,:),round(size(rip,2)/radonBinSize)); % 15 ms bins default (change on line 9)
                    end
                    % radon transform
                    [Pr,prMax] = placeBayes(rip_smooth',rateMaps{oo},radonBinSize/1000);
                    [slope,integral{o,oo}(iter)] = Pr2Radon(Pr');

%                     shuf = bz_shuffleCircular(rateMaps{oo});
%                     [Pr_shuf prMax] = placeBayes(rip_smooth',shuf,radonBinSize/1000);
%                     [slope_shuffle integral_shuffle{o,oo}(iter)] = Pr2Radon(Pr_shuf');

                    %% rank-order correlations
                    [~,~,ord] = sort_cells(rateMaps{oo}(keep,:));
%                     [a b ord_shuf] = sort_cells(shuf(keep,:));

                    [~,~,ord2] = sort_cells(rip(keep,:));

                    rankOrder{o,oo}(iter) = corr(ord,ord2);
%                     rankOrder_shuf{o,oo}(iter) = corr(ord_shuf,ord2);

                    %% reactivation analyses
                    R = ReactStrength(rateMaps{oo}',[ rip_smooth]','method','pca');
                    reactPCA{o,oo}(iter) = mean(R(:,1));
                    R = ReactStrength(rateMaps{oo}',[ rip_smooth]','method','ica');
                    reactICA{o,oo}(iter) = mean(R(:,1));
                end
                noise_rankOrd(nSub+1,nAdd+1,:) = (rankOrder{o,oo});
                noise_integral(nSub+1,nAdd+1,:) = (integral{o,oo});
                noise_reactICA(nSub+1,nAdd+1,:) = reactICA{o,oo};
                noise_reactPCA(nSub+1,nAdd+1,:) = reactPCA{o,oo};
            end
        end
        
        if display
        %Result of each stimulation
        figure(1)
        subplot(2,2,1)
        imagesc(rip)
        title('ripple example')
        
        subplot(2,2,2)
        imagesc(rateMaps{oo})
        title('PF ratemaps')
        
        subplot(2,2,3)
        plot(ord,ord2,'.k') % visualize what 'example' events look like as the simulations run
        xlabel('PF order')
        ylabel('ripple order')
        title(['removed: ' num2str(nSub) ', added: ' num2str(nAdd) ', rank order: ' num2str(rankOrder{o,oo}(end))])
        
        subplot(2,2,4)
        Pr2Radon(Pr',1); % visualize what 'example' events look like as the simulations run
        title(['removed: ' num2str(nSub) ', added: ' num2str(nAdd) ', radon integral: ' num2str(integral{o,oo}(end))])
        ylabel('decoded position')
        xlabel(['timebins (' num2str(radonBinSize) ' ms)'])
        
        drawnow
        end
        if nAdd==noiseBins-1 
        % Difference in Replay
        figure(2)
        subplot(1,2,1)
        imagesc(squeeze(mean(noise_rankOrd,3)));
        title('rank order')
        xlabel('# added "noise" spks')
        ylabel('# removed "real" spks')
        axis square
        colorbar
            xt = get(gca,'XTick');
            xt = [0 xt];
            set(gca,'XTick',xt+1)
            set(gca,'XTickLabel',xt*noiseStep)
            yt = get(gca,'YTick');
            yt = [0 yt];
            set(gca,'YTick',yt+1)
            set(gca,'YTickLabel',yt*noiseStep)     
        
        subplot(1,2,2)
        imagesc(squeeze(mean(noise_integral,3)));
        title('radon integral')
        xlabel('# added "noise" spks')
        ylabel('# removed "real" spks')
        axis square
        colorbar
            xt = get(gca,'XTick');
            xt = [0 xt];
            set(gca,'XTick',xt+1)
            set(gca,'XTickLabel',xt*noiseStep)
            yt = get(gca,'YTick');
            yt = [0 yt];
            set(gca,'YTick',yt+1)
            set(gca,'YTickLabel',yt*noiseStep)     
        
        % Difference in Reactivation
            figure(3)

            subplot(1,2,1)
            imagesc(squeeze(mean(noise_reactPCA,3)))
            title('react strength PCA')
            xlabel('# added "noise" spks')
            ylabel('# removed "real" spks')          
            axis square
            colorbar
            xt = get(gca,'XTick');
            xt = [0 xt];
            set(gca,'XTick',xt+1)
            set(gca,'XTickLabel',xt*noiseStep)
            yt = get(gca,'YTick');
            yt = [0 yt];
            set(gca,'YTick',yt+1)
            set(gca,'YTickLabel',yt*noiseStep)     

            subplot(1,2,2)
            imagesc(squeeze(mean(noise_reactICA,3)))
            title('react strength ICA')
            xlabel('# added "noise" spks')
            ylabel('# removed "real" spks')
            axis square
            colorbar
            xt = get(gca,'XTick');
            xt = [0 xt];
            set(gca,'XTick',xt+1)
            set(gca,'XTickLabel',xt*noiseStep)
            yt = get(gca,'YTick');
            yt = [0 yt];
            set(gca,'YTick',yt+1)
            set(gca,'YTickLabel',yt*noiseStep)     
        
%         
            drawnow
        end
            
        %pause(.001)
    end
end
fprintf('\n')