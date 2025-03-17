function StochasticOptimization_stoch
clc, clear, close all

%% DATA
% Time horizon (years)
Thoriz=25;


% for each bridge b:  beta0 mu_d(years) sigma_d(years) mu_L(years) sigma_L(years) C(Meuros)
data=[
    1 5  2/1.96 10 1/1.96 0.6
    1 6  1/1.96 11 2/1.96 0.8
    1 7  1/1.96 15 5/1.96 1    
    1 10 1/1.96 20 1/1.96 0.7   ];  % 95% within the range [mu-a,mu+a] --> sigma=a/1.96

[beta0_b, mud_b, sigd_b, muL_b, sigL_b, C_b]=deal(data(:,1), data(:,2), data(:,3), data(:,4), data(:,5), data(:,6));

% Annual resources (M euro)
R=1.4;

% Sample size of the probabilistic analysis
nMCS=20;

%--- Initial reliability estimation
nb=length(beta0_b); %number of bridges

% nMCS cases of d and L
[d_bi,L_bi]=deal(zeros(nb,nMCS));
for b=1:nb
    d_bi(b,:)=normrnd(mud_b(b),sigd_b(b),[1,nMCS]);
    L_bi(b,:)=normrnd(muL_b(b),sigL_b(b),[1,nMCS]);
end

beta_bti0=zeros(nb,Thoriz,nMCS);
for i=1:nMCS
    beta_bti0(:,:,i)=reliability(beta0_b,d_bi(:,i),L_bi(:,i),Thoriz);  %reliability with time
end

%--- figure ----
figure, hold on
col=['r','b','g','y'];
for i=1:nMCS
    for b=1:nb
        plot(1:Thoriz,beta_bti0(b,:,i),['-',col(b)],'LineWidth',0.5)
    end
end
for b=1:nb
    minbeta_t0=reliability(beta0_b(b),min(d_bi(b,:),[],2),min(L_bi(b,:),[],2),Thoriz);   %min reliability
    maxbeta_t0=reliability(beta0_b(b),max(d_bi(b,:),[],2),max(L_bi(b,:),[],2),Thoriz);   %max reliability
    plot(1:Thoriz,minbeta_t0,['-',col(b)],'LineWidth',3)
    plot(1:Thoriz,maxbeta_t0,['-',col(b)],'LineWidth',3)
end
grid on, xlim([1,Thoriz]), ylim([0,1]), xlabel('t (years)'), ylabel('\beta')
%--- ------ ----

%% Stochastic Optimization
%--- Variables ->  e.g., freq=[10 2 0 0 ; 5, 5 0 0; 0 0 0 0];  
maxInter_b=ceil(Thoriz./min(L_bi,[],2))+1; %max number of interventions expected per bridge given by the lowest service life

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
    ub(pos:pos+maxInter_b(b)-1)=max(L_bi(b,:),[],2)-1; % the largest service life is of relevance here
    % this forces zeros after the max number of interventions expected
    if maxInter_b(b)<nb
        ub(pos+maxInter_b(b):pos+nb-1)=0;
    end
    pos=pos+nt;
end
ub=ceil(ub);

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

        % Constraint 3 >>> Prob(beta_bt>0)>=0.95  --> sum(sum(beta_bt))<=0 for all b
        ProbRel_b=ProbFulfilment(beta_bti0,X_bt,Thoriz);
        c3 = 0.95-ProbRel_b;

        c=[c1;c2;c3];
        ceq =[]; %equalities are not allowed
    end

%--- Objective function: minimize cost trying to go for the largest time between interventions (== max y_b)
    function MinCost = fun(y_b)
        ninterv_b=CountNinterv(y_b, nt, nb);
        MinCost = C_b'*ninterv_b;
    end


%% Solution -----------------------------------------------------------
options=optimoptions('ga','StallGenLimit',1000); %('Display','none'); %'TolCon', 1e-9, 'TolFun', 1e-9,
[Yopt,MinCost,exitflag]=ga(@fun,nvars,Aineq,bineq,Aeq,beq,lb,ub,@nonlcon,IntCon, options);
OptInterv=cumulateFreq(reshape(Yopt, nt, nb)')
X_bt=Frequency2Schedule(Yopt, nb, nt, Thoriz)

%--- Result check
fprintf('Min Cost = %-6.2f\n',MinCost)
ninterv=sum(CountNinterv(Yopt, nt, nb));
fprintf('Number of interventions = %-4.0f\n',ninterv)
[c,~] = nonlcon(Yopt);
BudgetIssues=length(find(c(nb+1:nb+Thoriz)>0));
fprintf('Number of time intervals with exceeding budget = %-4.0f\n',BudgetIssues)
for b=1:nb
    probfulfilment=0.95-c(end-nb+b);
    fprintf('Prob(reliability>0) for bridge %1.0f = %-4.4f\n',b, probfulfilment)
end

%--- figure ----
figure, hold on
h=zeros(1,nb);leg=cell(1,4);
for b=1:nb, leg{b}=sprintf('Bridge %1.0f',b); end

for i=1:nMCS
    beta_bt=MaintenanceApplication(beta_bti0(:,:,i),X_bt,Thoriz); %optimal maintenance
    for b=1:nb
        h(b)=plot(1:Thoriz,beta_bt(b,:),['-',col(b)],'LineWidth',1);
    end
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

function ProbRel_b=ProbFulfilment(beta_bti0,X_bt,Thoriz)
[nb,~,nMCS]=size(beta_bti0);

%--- MCS
Achivement_bi=zeros(nb,nMCS);
for i=1:nMCS
    beta_bt=MaintenanceApplication(beta_bti0(:,:,i),X_bt,Thoriz);
    failures_b=sum(beta_bt==0,2);
    Achivement_bi(:,i)=(failures_b==0);
end
ProbRel_b=sum(Achivement_bi,2)/nMCS;
end