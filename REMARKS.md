## Remarks 

This section provides a short description of remarks that have not been mentioned elsewhere in the project description. 

### I-LOC without B-LOC

At times, the sequence tagger found two-part locations in which only the I-LOC was the actual location as the B-LOC was not of relevance. After a careful examination of these few cases, we decided to not include them in the geocoding stage. An example of the issue is provided below:

```
data/sn85066408_1903-08-25_ed-1_seq-1_ocr.txt
             raw     lowercased     col2 col3   type  col5  group_id_column
0  Kirk-Kilioseh  kirk-kilioseh  UNKNOWN    O  I-LOC   NaN              NaN

data/sn85066408_1904-08-11_ed-1_seq-1_ocr.txt
         raw lowercased     col2 col3   type  col5  group_id
0    Formosa    formosa  UNKNOWN    O  I-LOC   NaN       NaN <== first LOC starts with I
1        via        via    KNOWN    O  B-LOC   NaN       1.0
2   Brindisi   brindisi    KNOWN    O  I-LOC   NaN       NaN
3        Mar        mar    KNOWN    O  B-LOC   NaN       3.0
```

### Location

In the case of multi-name locations, the sequence tagger only tagged parts of it. Consider the example below:

```
Costa	costa	KNOWN	O	B-LOC
del	del	KNOWN	O	O
Pacifico	pacifico	KNOWN	O	B-LOC
```
*Costa del Pacifico* is classified as 'Costa' and 'Pacifico'. 

### Sequence Tagger F1 score
The model was computed with a Bi-LSTM NER tagger (see [Riedl and Pado' 2008](https://www.aclweb.org/anthology/P18-2020.pdf)). The results of the F1 score of sequence tagging for Italian models are:

**accuracy:  98.15%; precision:  83.64%; recall:  82.14%; FB1:  82.88**

              GPE: precision:  83.90%; recall:  86.18%; FB1:  85.02  1174
              LOC: precision:  69.70%; recall:  44.23%; FB1:  54.12  99
              ORG: precision:  73.36%; recall:  73.08%; FB1:  73.22  1284
              PER: precision:  89.78%; recall:  87.59%; FB1:  88.68  2320

Embeddings were computed using Italian Wikipedia that have been trained using Fastext with 300 dimensions (see https://fasttext.cc/docs/en/crawl-vectors.html).


### OCR issues
The newspapers in [*ChroniclItaly*](https://public.yoda.uu.nl/i-lab/UU01/T4YMOW.html) were digitized primarily from microfilm holdings. In addition to the well-known limitations for OCR processes such as unusual text styles or very small fonts, other limitations occur when dealing with old material, including markings on the pages or a general poor condition of the original text. Such limitations also apply to the OCR-generated searchable texts in *ChroniclItaly* which therefore contain errors. However, the OCR quality was found better in the most recent texts, perhaps due to a better conservation status or better initial condition of the originals which overall improved over the course of the nineteenth century. Therefore, the quality of the OCR data can vary greatly even within the same newspaper. 
The OCR error limitation can however be at least partially overcome in two ways: first, it is reasonable to assume that important concept words would have been repeated several times within an article thus increasing the likelihood that OCR read them correctly in at least some of the passages. Second, the geo-coding was restricted to place names that were referred to at least more than 8 times across the whole collection.

### Other remarks
To improve the user experience of the GNM app, a number of methodological decisions were taken. For instance, adding all the categories of locations to the GNM App would have significantly decreased the quality of the visualisation. Therefore, one decision concerned determining the categories of locations to not add to the GNM App. These categories are:

- Natural features: locations identified by Google as `natural feature` such as lakes, mountains, rivers, oceans, etc.;
- Continents and regional areas: locations such as *the Balkans*, *Scandinavia*, *the Pacific coast*, etc.; 
- Historical places: places that were referred to in reference to an event such as *Piave* or *Porto Arthur*.

Another decision concerned the legend and the colour scheme. The colour scheme of the map reflects the number of newspapers' pages that include references to place names and *not* the absolute number of place names occurrences across the dataset. This decision was made to obtain a more homogenous coulor variation. When hovering over each place (e.g., country, city, region), a pop-up text displays the relevant details (i.e., absolute frequency, number of pages in which the place occurs, number of newspapars' titles, percentage).

Users have full access to the raw data so that they can always obtain information on frequency of occurrence, type of reference, etc.
