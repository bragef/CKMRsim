#include <Rcpp.h>
using namespace Rcpp;

//' Compute pairwise relationship measures between all individuals in source and one individual in target
//'
//' More explanation later.
//'
//' @param S "source", a matrix whose rows are integers, with NumInd-source rows and NumLoci columns, with each
//' entry being a a base-0 representation of the genotype of the c-th locus at the r-th individual.
//' These are the individuals you can think of as parents if there is directionality to the
//' comparisons.
//' @param T "target",  a matrix whose rows are integers, with NumInd-target rows and NumLoci columns, with each
//' entry being a a base-0 representation of the genotype of the c-th locus at the r-th individual.
//' These are the individuals you can think of as offspring if there is directionality to the
//' comparisons.
//' @param t the index (base-1) of the individual in T that you want to compare against
//' everyone on S.
//' @param values the vector of genotype specific values.  See the probs field of \code{\link{flatten_ckmr}}.
//' @param nGenos a vector of the number of genotypes at each locus
//' @param base0_locus_starts the base0 indexes of the starting positions of each locus in probs.
//'
//' @return a data frame with columns "ind" (the base-1 index of the individual in S),
//' "value" (the value extracted, typically a log likelihood ratio), and "num_loc" (the
//' number of non-missing loci in the comparison.)
//' @export
// [[Rcpp::export]]
DataFrame comp_ind_pairwise(IntegerMatrix S, IntegerMatrix T, int t, NumericVector values, IntegerVector nGenos, IntegerVector Starts) {
  int L = S.ncol();
  int nS = S.nrow();
  int i,j,n;
  int tG, sG;
  double sum;
  IntegerVector popi(nS);
  NumericVector val(nS);
  IntegerVector nonmiss(nS);  // for the number of non_missing loci


  for(i=0;i<nS;i++) {
    sum = 0.0;
    n = 0;
    for(j=0;j<L;j++) {
      tG = T(t - 1, j);
      sG = S(i, j);
      if(tG >=0 && sG >= 0) {  // if both individuals have non-missing data
        n++;
        sum += values[Starts[j] + nGenos[j] * sG + tG];
      }
    }
    popi[i] = i + 1;
    val[i] = sum;
    nonmiss[i] = n;
  }

  return(DataFrame::create(Named("ind") = popi,
                           Named("value") = val,
                           Named("num_loc") = nonmiss));
}





//' Return every pair of individuals that mismatch at no more than max_miss loci
//'
//' This is used for identifying duplicate individuals/genotypes in large
//' data sets. I've specified this in terms of the max number of missing loci because
//' I think everyone should already have tossed out individuals with a lot of
//' missing data, and then it makes it easy to toss out pairs without even
//' looking at all the loci, so it is faster for all the comparisons.
//'
//' @param S "source", a matrix whose rows are integers, with NumInd-source rows and NumLoci columns, with each
//' entry being a a base-0 representation of the genotype of the c-th locus at the r-th individual.
//' These are the individuals you can think of as parents if there is directionality to the
//' comparisons.  Missing data is denoted by -1 (or any integer < 0).
//' @param max_miss maximum allowable number of mismatching genotypes betwen the pairs.
//' @return a data frame with columns:
//' \describe{
//'   \item{ind1}{the base-1 index in S of the first individual of the pair}
//'   \item{ind2}{the base-1 index in S of the second individual of the pair}
//'   \item{num_mismatch}{the number of loci at which the pair have mismatching genotypes}
//'   \item{num_loc}{the total number of loci missing in neither individual}
//' }
//' @export
// [[Rcpp::export]]
DataFrame pairwise_geno_id(IntegerMatrix S, int max_miss) {
  int L = S.ncol();
  int nS = S.nrow();
  int i,j,l,n,mm, bailed = 0;
  int G1, G2;
  std::vector<int> ind1;
  std::vector<int> ind2;
  std::vector<int> num_mismatch;
  std::vector<int> num_loc;


  for(i=0;i<nS;i++) {
    for(j=i+1;j<nS;j++) {
      mm = 0;
      n = 0;
      bailed = 0;
      for(l=0;l<L;l++) {
        G1 = S(i, l);
        G2 = S(j, l);
        if(G1 >=0 && G2 >= 0) {  // if both individuals have non-missing data
          n++;
          mm += G1 != G2;
        }
        if(mm > max_miss) {
          bailed = 1;
          break;
        }
      }
      if(bailed == 0) {  // if we didn't bail 'cuz there were too many mismatching genotypes
        ind1.push_back(i + 1);
        ind2.push_back(j + 1);
        num_mismatch.push_back(mm);
        num_loc.push_back(n);
      }
    }
  }

  return(DataFrame::create(Named("ind1") = ind1,
                           Named("ind2") = ind2,
                           Named("num_mismatch") = num_mismatch,
                           Named("num_loc") = num_loc));
}
