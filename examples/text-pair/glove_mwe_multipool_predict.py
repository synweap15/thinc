from __future__ import unicode_literals, print_function
import plac
import spacy
from pathlib import Path
import dill as pickle

from thinc.neural import Model, Softmax, Maxout
from thinc.neural import ExtractWindow
from thinc.neural.pooling import Pooling, mean_pool, max_pool
from thinc.neural._classes.static_vectors import StaticVectors, get_word_ids
from thinc.neural._classes.embed import Embed
from thinc.neural._classes.difference import Siamese, WordMoversSimilarity, CauchySimilarity

from thinc.api import layerize, with_flatten
from thinc.api import add, chain, clone, concatenate, Arg

from thinc.extra import datasets
from thinc.extra.load_nlp import get_spacy, get_vectors


epoch_train_acc = 0.
def track_progress(**context):
    '''Print training progress. Called after each epoch.'''
    model = context['model']
    train_X = context['train_X']
    dev_X = context['dev_X']
    dev_y = context['dev_y']
    n_train = len(train_X)
    trainer = context['trainer']
    def each_epoch():
        global epoch_train_acc
        acc = model.evaluate(dev_X, dev_y)
        with model.use_params(trainer.optimizer.averages):
            avg_acc = model.evaluate(dev_X, dev_y)
        stats = (acc, avg_acc, float(epoch_train_acc) / n_train, trainer.dropout)
        print("%.3f (%.3f) dev acc, %.3f train acc, %.4f drop" % stats)
        epoch_train_acc = 0.
    return each_epoch


def preprocess(ops, nlp, rows):
    '''Parse the texts with spaCy. Make one-hot vectors for the labels.'''
    Xs = []
    ys = []
    for (text1, text2), label in rows:
        Xs.append((nlp(text1), nlp(text2)))
        ys.append(label)
    return Xs, ops.asarray(ys)


def diff(layer):
    ops = layer.ops
    def forward(inputs, drop=0.):
        inputs1, inputs2 = zip(*inputs)
        X1, bp_X1 = layer.begin_update(inputs1, drop=drop)
        X2, bp_X2 = layer.begin_update(inputs2, drop=drop)
        piece1 = X1 - X2
        piece2 = X1 * X2
        output = ops.xp.hstack((piece1, piece2))
        output = piece2

        def backward(d_output, sgd=None):
            assert d_output.shape == output.shape
            d_piece1 = d_output[:, :X1.shape[1]]
            d_piece2 = d_output[:, X2.shape[1]:]
            d_X1 = (d_piece2 * X2) + d_piece1
            d_X2 = (d_piece2 * X1) - d_piece1
            d_input1 = bp_X1(d_X1, sgd)
            d_input2 = bp_X2(d_X2, sgd)
            if d_input1 and d_input2:
                return zip(d_input1, d_input2)
            else:
                return None
        return output, backward
    model = layerize(forward)
    model._layers.append(layer)
    return model


@plac.annotations(
    dataset=("Dataset to load"),
    width=("Width of the hidden layers", "option", "w", int),
    depth=("Depth of the hidden layers", "option", "d", int),
    min_batch_size=("Minimum minibatch size during training", "option", "b", int),
    max_batch_size=("Maximum minibatch size during training", "option", "B", int),
    dropout=("Dropout rate", "option", "D", float),
    dropout_decay=("Dropout decay", "option", "C", float),
    use_gpu=("Whether to use GPU", "flag", "G", bool),
    nb_epoch=("Number of epochs", "option", "i", int),
    pieces=("Number of pieces for maxout", "option", "p", int),
    out_loc=("File to save the model", "option", "o"),
    quiet=("Don't print the progress bar", "flag", "q"),
    pooling=("Which pooling to use", "option", "P", str)
)
def main(dataset='quora', width=128, depth=2, min_batch_size=128,
        max_batch_size=128, dropout=0.0, dropout_decay=0.0, pooling="mean+max",
        nb_epoch=20, pieces=3, use_gpu=False, out_loc=None, quiet=False):
    cfg = dict(locals())
    if out_loc:
        out_loc = Path(out_loc)
        if not out_loc.parent.exists():
            raise IOError("Can't open output location: %s" % out_loc)
    print(cfg)
    if pooling == 'mean+max':
        pool_layer = Pooling(mean_pool, max_pool)
    elif pooling == "mean":
        pool_layer = mean_pool
    elif pooling == "max":
        pool_layer = max_pool
    else:
        raise ValueError("Unrecognised pooling", pooling)


    print("Load spaCy")
    nlp = get_spacy('en')

    if use_gpu:
        Model.ops = CupyOps()

    print("Construct model")
    # Bind operators for the scope of the block:
    # * chain (>>): Compose models in a 'feed forward' style,
    # i.e. chain(f, g)(x) -> g(f(x))
    # * clone (**): Create n copies of a model, and chain them, i.e.
    # (f ** 3)(x) -> f''(f'(f(x))), where f, f' and f'' have distinct weights.
    # * concatenate (|): Merge the outputs of two models into a single vector,
    # i.e. (f|g)(x) -> hstack(f(x), g(x))
    with Model.define_operators({'>>': chain, '**': clone, '|': concatenate,
                                 '+': add}):
        mwe_encode = ExtractWindow(nW=1) >> Maxout(width, width*3, pieces=pieces)

        embed = StaticVectors('en', width) + Embed(width, width, 5000)
        sent2mat = (
            get_word_ids(Model.ops)
            >> with_flatten(embed >> mwe_encode ** depth)
        )
        model = Siamese(sent2mat,
                    WordMoversSimilarity(Model.ops))


    print("Read and parse data: %s" % dataset)
    if dataset == 'quora':
        train, dev = datasets.quora_questions()
    elif dataset == 'snli':
        train, dev = datasets.snli()
    else:
        raise ValueError("Unknown dataset: %s" % dataset)
    train_X, train_y = preprocess(model.ops, nlp, train)
    dev_X, dev_y = preprocess(model.ops, nlp, dev)
    print("Initialize with data (LSUV)")
    with model.begin_training(train_X[:5000], train_y[:5000], **cfg) as (trainer, optimizer):
        # Pass a callback to print progress. Give it all the local scope,
        # because why not?
        trainer.each_epoch.append(track_progress(**locals()))
        trainer.batch_size = min_batch_size
        batch_size = float(min_batch_size)
        print("Accuracy before training", model.evaluate(dev_X, dev_y))
        print("Train")
        global epoch_train_acc
        for X, y in trainer.iterate(train_X[:500], train_y[:500], progress_bar=not quiet):
            # Slightly useful trick: Decay the dropout as training proceeds.
            yh, backprop = model.begin_update(X, drop=trainer.dropout)
            # No auto-diff: Just get a callback and pass the data through.
            # Hardly a hardship, and it means we don't have to create/maintain
            # a computational graph. We just use closures.

            train_acc = ((yh>=0.5) == (y>=0.5)).sum()
            epoch_train_acc += train_acc

            backprop(yh-y, optimizer)

            # Slightly useful trick: start with low batch size, accelerate.
            trainer.batch_size = min(int(batch_size), max_batch_size)
            batch_size *= 1.001
        if out_loc:
            out_loc = Path(out_loc)
            print('Saving to', out_loc)
            with out_loc.open('wb') as file_:
                pickle.dump(model, file_, -1)


if __name__ == '__main__':
    if 1:
        plac.call(main)
    else:
        import cProfile
        import pstats
        cProfile.runctx("plac.call(main)", globals(), locals(), "Profile.prof")
        s = pstats.Stats("Profile.prof")
        s.strip_dirs().sort_stats("time").print_stats(100)
