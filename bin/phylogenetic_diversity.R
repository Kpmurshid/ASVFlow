args <- commandArgs(trailingOnly=TRUE)
if (length(args) != 4) stop('Usage: phylogenetic_diversity.R <phyloseq.rds> <tree.nwk|NO_TREE> <output-dir> <metadata.tsv|NO_METADATA>')
ps_file <- args[[1]]; tree_file <- args[[2]]; outdir <- args[[3]]; metadata_file <- args[[4]]
if (!file.exists(ps_file)) stop('phyloseq RDS does not exist: ', ps_file)
if (!dir.exists(outdir)) stop('Output directory does not exist: ', outdir)
if (basename(tree_file) == 'NO_TREE') {
  write.table(data.frame(sample_id=character(),Faith_PD=numeric(),Faith_PD_status=character(),Faith_PD_rooting=character()),file.path(outdir,'faith_pd.tsv'),sep='\t',quote=FALSE,row.names=FALSE)
  writeLines('unavailable: no tree emitted by phylogenetic analysis',file.path(outdir,'phylogenetic_diversity_status.txt'))
  for (metric in c('weighted','unweighted')) write.table(data.frame(sample_id=character(),PC1=numeric(),PC2=numeric()),file.path(outdir,paste0('beta_diversity_',metric,'_unifrac_pcoa.tsv')),sep='\t',quote=FALSE,row.names=FALSE)
  write.table(data.frame(metric=character(),PC=integer(),eigenvalue=numeric(),variance_explained=numeric()),file.path(outdir,'beta_diversity_phylogenetic_stats.tsv'),sep='\t',quote=FALSE,row.names=FALSE)
  saveRDS(as.dist(matrix(numeric(),0,0)),file.path(outdir,'beta_diversity_distances_weighted_unifrac.rds'))
  saveRDS(as.dist(matrix(numeric(),0,0)),file.path(outdir,'beta_diversity_distances_unweighted_unifrac.rds'))
  quit(save='no',status=0)
}
if (!file.exists(tree_file)) stop('Tree input does not exist: ',tree_file)
suppressPackageStartupMessages({library(phyloseq);library(ape);library(picante)})
ps<-readRDS(ps_file); otu<-as(otu_table(ps),'matrix'); if(taxa_are_rows(ps)) otu<-t(otu)
tr<-read.tree(tree_file)
if(is.null(tr$edge.length)||any(!is.finite(tr$edge.length))||any(tr$edge.length<0)) stop('Tree has invalid branch lengths')
if(anyDuplicated(tr$tip.label)) stop('Duplicate tree tip IDs')
if(!setequal(colnames(otu),tr$tip.label)) stop('ASV ID mismatch: table-only=',paste(setdiff(colnames(otu),tr$tip.label),collapse=','),'; tree-only=',paste(setdiff(tr$tip.label,colnames(otu)),collapse=','))
otu<-otu[,tr$tip.label,drop=FALSE]; if(Ntip(tr)<2) stop('Tree needs at least two tips')
rooted<-root(tr,outgroup=tr$tip.label[1],resolve.root=TRUE); nz<-rowSums(otu)>0
if (!is.rooted(rooted)) stop('ape::root did not produce a rooted tree')
faith<-rep(NA_real_,nrow(otu)); names(faith)<-rownames(otu); faith[nz]<-pd(otu[nz,,drop=FALSE],rooted,include.root=TRUE)$PD
meta<-as(sample_data(ps),'data.frame')
faith_df<-data.frame(sample_id=names(faith),Faith_PD=faith,Faith_PD_status=ifelse(nz,'ok','zero_reads'),Faith_PD_rooting=paste0('ape::root outgroup ',tr$tip.label[1]))
for(nm in colnames(meta)) faith_df[[nm]]<-meta[match(faith_df$sample_id,rownames(meta)),nm]
write.table(faith_df,file.path(outdir,'faith_pd.tsv'),sep='\t',quote=FALSE,row.names=FALSE)
if (sum(nz) < 2) {
  ids <- rownames(otu)[nz]; empty_dist <- as.dist(matrix(0,length(ids),length(ids),dimnames=list(ids,ids)))
  saveRDS(empty_dist,file.path(outdir,'beta_diversity_distances_weighted_unifrac.rds')); saveRDS(empty_dist,file.path(outdir,'beta_diversity_distances_unweighted_unifrac.rds'))
  reason <- 'fewer than two non-zero samples'
  for (metric in c('weighted','unweighted')) write.table(data.frame(sample_id=ids,PC1=NA_real_,PC2=NA_real_,ordination_status='unavailable',ordination_reason=reason),file.path(outdir,paste0('beta_diversity_',metric,'_unifrac_pcoa.tsv')),sep='\t',quote=FALSE,row.names=FALSE)
  write.table(data.frame(metric=c('weighted_unifrac','unweighted_unifrac'),PC=NA_integer_,eigenvalue=NA_real_,variance_explained=NA_real_,status='unavailable',reason=reason),file.path(outdir,'beta_diversity_phylogenetic_stats.tsv'),sep='\t',quote=FALSE,row.names=FALSE)
  writeLines(c('unavailable',reason),file.path(outdir,'phylogenetic_diversity_status.txt')); quit(save='no',status=0)
}
subps<-prune_samples(rownames(otu)[nz],ps); prune_taxa(tr$tip.label,subps)->subps; phy_tree(subps)<-rooted
if (!is.rooted(phy_tree(subps))) stop('Weighted UniFrac input tree is not rooted')
cat('Tree rooted before weighted UniFrac:',is.rooted(phy_tree(subps)),'\n')
w<-UniFrac(subps,weighted=TRUE,normalized=TRUE,parallel=FALSE)
if (!is.rooted(phy_tree(subps))) stop('Unweighted UniFrac input tree is not rooted')
cat('Tree rooted before unweighted UniFrac:',is.rooted(phy_tree(subps)),'\n')
u<-UniFrac(subps,weighted=FALSE,normalized=TRUE,parallel=FALSE)
check<-function(d){m<-as.matrix(d);if(any(!is.finite(m))||!isTRUE(all.equal(m,t(m)))||any(diag(m)!=0))stop('Invalid UniFrac distance matrix');d}
w<-check(w);u<-check(u)
saveRDS(w,file.path(outdir,'beta_diversity_distances_weighted_unifrac.rds'));saveRDS(u,file.path(outdir,'beta_diversity_distances_unweighted_unifrac.rds'))
ord<-function(d,metric){m<-as.matrix(d);ids<-rownames(m); n<-nrow(m); H<-diag(n)-matrix(1/n,n,n); B<--0.5*H%*%(m^2)%*%H;eigen_result<-eigen(B,symmetric=TRUE);pos<-which(eigen_result$values>sqrt(.Machine$double.eps));coords<-matrix(NA_real_,n,2);if(length(pos))coords[,seq_len(min(2,length(pos)))]<-sweep(eigen_result$vectors[,seq_len(min(2,length(pos))),drop=FALSE],2,sqrt(eigen_result$values[seq_len(min(2,length(pos)))]),'*');available<-length(pos)>0;reason<-if(available)'' else if(n<2)'fewer than two non-zero samples' else 'no positive PCoA eigenvalues';df<-data.frame(sample_id=ids,PC1=coords[,1],PC2=coords[,2],ordination_status=if(available)'available' else 'unavailable',ordination_reason=reason);for(nm in colnames(meta))df[[nm]]<-meta[match(ids,rownames(meta)),nm];write.table(df,file.path(outdir,paste0('beta_diversity_',metric,'_unifrac_pcoa.tsv')),sep='\t',quote=FALSE,row.names=FALSE);if(!available)return(data.frame(metric=paste0(metric,'_unifrac'),PC=NA_integer_,eigenvalue=NA_real_,variance_explained=NA_real_,status='unavailable',reason=reason));den<-sum(eigen_result$values[eigen_result$values>0]);data.frame(metric=paste0(metric,'_unifrac'),PC=pos,eigenvalue=eigen_result$values[pos],variance_explained=eigen_result$values[pos]/den*100,status='available',reason='')}
stats<-rbind(ord(w,'weighted'),ord(u,'unweighted'));write.table(stats,file.path(outdir,'beta_diversity_phylogenetic_stats.tsv'),sep='\t',quote=FALSE,row.names=FALSE)
writeLines(c('available',paste0('Faith PD rooting: ape::root outgroup ',tr$tip.label[1]),'Original FastTree tree unchanged. UniFrac uses unrooted topology.'),file.path(outdir,'phylogenetic_diversity_status.txt'))
