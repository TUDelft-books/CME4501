function StochasticOptimization_Rob
clc, clear, close all

%% DATA
% Time horizon (years)
Thoriz=25;


% for each bridge b:  beta0 d1(years) d2(years) L1(years) L2(years) C(Meuros)
data=[
%     1 5 5 10 10 0.6
%     1 6 6 11 11 0.8
%     1 7 7 15 15 1    
%     1 10 10 20 20 0.7   ];

1 3 7 9 11 0.6
1 5 7 9 13 0.8
1 6 8 10 20 1
1 9 11 19 21 0.7];
[beta0_b, d1_b, d2_b, L1_b, L2_b, C_b]=deal(data(:,1), data(:,2), data(:,3), data(:,4), data(:,5), data(:,6));

% Annual resources (M euro)
R=1.4;


%--- Initial reliability estimation
nb=length(beta0_b); %number of bridges
beta_bt01=reliability(beta0_b,d1_b,L1_b,Thoriz);  %lowest reliability with time 
beta_bt02=reliability(beta0_b,d2_b,L2_b,Thoriz);  %largest reliability with time

 %--- figure ----
figure, hold on
col=['r','b','g','y'];
for b=1:nb
    plot(1:Thoriz,beta_bt01(b,:),['-',col(b)],'LineWidth',2)  
    plot(1:Thoriz,beta_bt02(b,:),['-',col(b)],'LineWidth',2)  
end
grid on, xlim([1,Thoriz]), ylim([0,1]), xlabel('t (years)'), ylabel('\beta')
%--- ------ ----

%% Robust Optimization
%--- Variables ->  e.g., freq=[10 2 0 0 ; 5, 5 0 0; 0 0 0 0];  
maxInter_b=ceil(Thoriz./L1_b)+1; %max number of interventions expected per bridge given by the lowest service life

nt=max(maxInter_b); %to dimension the matrix, max interventions experienced by the worst case. 
nvars=nb*nt; %number of design variables   y_b=[10 2 0 0 , 5, 5 0 0, 0 0 0 0]'
IntCon=1:nvars;  %the position of the integer variables

%--- Range of definition: [0,max number of years with no interventions==L_b]
% lower bound
lb=zeros(nvars,1);
% upper bound
ub=lb;
pos=1;
for b=1:nb
    % This guarantees interventions freq. within the service life (if conducted)
    ub(pos:pos+maxInter_b(b)-1)=L2_b(b)-1; % the largest service life is of relevance here
    % this forces zeros after the max number of interventions expected
    if maxInter_b(b)<nb
        ub(pos+maxInter_b(b):pos+nb-1)=0;
    end
    pos=pos+nt;
end

%--- Linear constraints
Aineq=[];bineq=[]; % Inequality constraints
Aeq=[]; beq=[];% Equality constraints

%--- Nonlinear constraints
    function [c,ceq] = nonlcon(y_b)
        %From frequency to a schedule matrix [0/1]
        X_bt = Frequency2Schedule(y_b, nb, nt, Thoriz);

        % Constraint 1 >>> the last intervention is within Thoriz --> LastInterv<Thoriz --> LastInterv-Thoriz<=1   for all b
        lastInterv_b = max(cumulateFreq(reshape(y_b, nt, nb)'),[],2); %the last intervention
        c1 = lastInterv_b-Thoriz-1;

        % Constraint 2 >>> C_b*X_bt <= R   for all t
        c2 = (sum(repmat(C_b,1,Thoriz).*X_bt)-R)';

        % Constraint 3 >>> beta_bt>0 for the lowest reliability
        beta_bt=MaintenanceApplication(beta_bt01,X_bt,Thoriz);
        c3 = sum(sum(beta_bt==0)); 

        % Constraint 4 >>> beta_bt>0 for the highest reliability
        beta_bt=MaintenanceApplication(beta_bt02,X_bt,Thoriz);
        c4 = sum(sum(beta_bt==0));

        c=[c1;c2;c3;c4];
        ceq =[]; %equalities are not allowed
    end

%--- Objective function: minimize cost trying to go for the largest time between interventions (== max y_b)
    function MinCost = fun(y_b)
        ninterv_b=CountNinterv(y_b, nt, nb);
        MinCost = C_b'*ninterv_b;
    end


%% Solution -----------------------------------------------------------
options=optimoptions('ga','Generations',10000*nvars,'StallGenLimit',1000); %('Display','none'); %'TolCon', 1e-9, 'TolFun', 1e-9,
[Yopt,MinCost,exitflag]=ga(@fun,nvars,Aineq,bineq,Aeq,beq,lb,ub,@nonlcon,IntCon, options);
OptInterv=cumulateFreq(reshape(Yopt, nt, nb)')
X_bt=Frequency2Schedule(Yopt, nb, nt, Thoriz)
beta1_bt=MaintenanceApplication(beta_bt01,X_bt,Thoriz); %optimal maintenance 
beta2_bt=MaintenanceApplication(beta_bt02,X_bt,Thoriz); %optimal maintenance 

%--- Result check
fprintf('Min Cost = %-6.2f\n',MinCost)
ninterv=sum(CountNinterv(Yopt, nt, nb));
fprintf('Number of interventions = %-4.0f\n',ninterv)
[c,~] = nonlcon(Yopt);
BudgetIssues=length(find(c(end-Thoriz-1:end-2)>0));
fprintf('Number of time intervals with exceeding budget = %-4.0f\n',BudgetIssues)
reliabIssues=c(end-1)+c(end);
fprintf('Number of time intervals with reliability issues = %-4.0f\n',reliabIssues)

%--- figure ----
figure, hold on
h=zeros(1,nb);leg=cell(1,4);
for b=1:nb
    h(b)=plot(1:Thoriz,beta1_bt(b,:),['--',col(b)],'LineWidth',1);  
    plot(1:Thoriz,beta2_bt(b,:),['-',col(b)],'LineWidth',1) 
    leg{b}=sprintf('Bridge %1.0f',b);
end
grid on, xlim([1,Thoriz]), ylim([0,1]), xlabel('t (years)'), ylabel('\beta')
legend(h, leg, 'Location', 'best')
%--- ------ ----

end


%%%%%%%%%%%%%%%%%%%%%%%%%%
function beta_bt=reliability(beta0_b,d_b,L_b,Thoriz)
%--- Reliability estimation
% beta_bt reliability curve over time for bridge b
% beta0_b: Initial reliability of bridge b at t=0
% d_b,L_b: when the degradation starts and reaches beta=0 for each bridge
% Thoriz: maximum time studied

nb=length(beta0_b); %number of bridges
beta_bt=zeros(nb,Thoriz);
%introducting degradation: beta(t)=beta0/(L-d)*(L-t)

for b=1:nb
    %horizontal branch
    timesteps=floor(d_b(b));
    beta_bt(b,1:timesteps)=beta0_b(b)*ones(1,timesteps);

    %degradation till L_b
    servicelife=floor(L_b(b));
    t=timesteps+1:servicelife;
    beta_bt(b,timesteps+1:servicelife)=beta0_b(b)./(L_b(b)-d_b(b)).*(L_b(b)-t);
end
end

function updatedbeta_bt=MaintenanceApplication(beta_bt,X_bt,Thoriz)
%--- given a maintenance strategy given by X_bt, where 1 means that bridge
% b undergoes maintenance at time t, this function gives the updated
% reliability profile

updatedbeta_bt=beta_bt;%it reads the previous beta and to correct it after t1
InterventionTimes=find(sum(X_bt)>0); %indicates the time steps with interventions

for t=InterventionTimes
    intervbrid=find(X_bt(:,t)==1);%for the bridges intervened at a given t

    %introducting degradation: beta(t)=beta0/(L-d)*(L-t)
    timecells=Thoriz-t;
    updatedbeta_bt(intervbrid,t+1:Thoriz)=beta_bt(intervbrid,1:timecells); %it takes the shape of the original curve
end
end

function X_bt = Frequency2Schedule(y_b, nb, nt, Thoriz)
% Transforms a vector indicating the frequency to a schedule matrix [0/1]
freq_b=reshape(y_b, nt, nb)'; %from vector to matrix
cumFreq_b = cumulateFreq(freq_b); %creates the cumulative frequency->gives the years of interventions
X_bt = zeros(nb, Thoriz);

for b = 1:nb
    % Extract nonzero entries, which are assumed to be column indices
    idx = cumFreq_b(b, cumFreq_b(b, :) ~= 0);

    %substract the idx>T
    idx = idx(idx<=Thoriz); 

    % If nonzero indices exist, set corresponding positions in X_bt to one
    if ~isempty(idx)
        X_bt(b, idx) = 1;
    end
end
end

function cumFreq_b = cumulateFreq(freq_b)
%creates the cumulative frequency
[nb, nt] = size(freq_b);
cumFreq_b = zeros(nb, nt);

for b=1:nb
    f_b=freq_b(b,freq_b(b,:)~=0); %frequencies
    cumFreq_b(b,1:length(f_b))=cumsum(f_b); %years when the intervention is done
end
end

function ninterv_b=CountNinterv(y_b, nt, nb)
%from vector y_b, it computes the number of interventions per bridge
y_b01=y_b~=0;
freq_b=reshape(y_b01, nt, nb)';  %it creates the matrix
ninterv_b=sum(freq_b,2);% it evaluates the number of interventions
end