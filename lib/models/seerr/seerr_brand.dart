/// A film studio or a TV network, as a tile on the Explore shelf.
///
/// Seerr serves no list of either — its own website carries fixed ones in its
/// source, and so does this app, mirroring them entry for entry so the shelves
/// show what the website shows. The lists follow Jellyseerr's `StudioSlider`
/// and `NetworkSlider` (github.com/Fallenbagel/jellyseerr, MIT License). [logoPath] is a TMDB image path; the duotone
/// rendition Seerr uses keeps every logo legible on a dark tile, whatever
/// colours the original has.
class SeerrBrand {
  final int id;
  final String name;
  final String logoPath;

  const SeerrBrand({required this.id, required this.name, required this.logoPath});

  /// The logo, rendered white-on-grey the way the Seerr website renders it.
  String logoUrl() => 'https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)$logoPath';
}

/// The film studios of Seerr's own discover page, in its order.
const List<SeerrBrand> kSeerrStudios = [
  SeerrBrand(id: 2, name: 'Disney', logoPath: '/wdrCwmRnLFJhEoH8GSfymY85KHT.png'),
  SeerrBrand(id: 127928, name: '20th Century Studios', logoPath: '/h0rjX5vjW5r8yEnUBStFarjcLT4.png'),
  SeerrBrand(id: 34, name: 'Sony Pictures', logoPath: '/GagSvqWlyPdkFHMfQ3pNq6ix9P.png'),
  SeerrBrand(id: 174, name: 'Warner Bros. Pictures', logoPath: '/ky0xOc5OrhzkZ1N6KyUxacfQsCk.png'),
  SeerrBrand(id: 33, name: 'Universal', logoPath: '/8lvHyhjr8oUKOOy2dKXoALWKdp0.png'),
  SeerrBrand(id: 4, name: 'Paramount', logoPath: '/fycMZt242LVjagMByZOLUGbCvv3.png'),
  SeerrBrand(id: 3, name: 'Pixar', logoPath: '/1TjvGVDMYsj6JBxOAkUHpPEwLf7.png'),
  SeerrBrand(id: 521, name: 'DreamWorks', logoPath: '/kP7t6RwGz2AvvTkvnI1uteEwHet.png'),
  SeerrBrand(id: 420, name: 'Marvel Studios', logoPath: '/hUzeosd33nzE5MCNsZxCGEKTXaQ.png'),
  SeerrBrand(id: 9993, name: 'DC', logoPath: '/2Tc1P3Ac8M479naPp1kYT3izLS5.png'),
  SeerrBrand(id: 41077, name: 'A24', logoPath: '/1ZXsGaFPgrgS6ZZGS37AqD5uU12.png'),
];

/// The TV networks and streaming services of Seerr's own discover page, in its
/// order.
const List<SeerrBrand> kSeerrNetworks = [
  SeerrBrand(id: 213, name: 'Netflix', logoPath: '/wwemzKWzjKYJFfCeiB57q3r4Bcm.png'),
  SeerrBrand(id: 2739, name: 'Disney+', logoPath: '/gJ8VX6JSu3ciXHuC2dDGAo2lvwM.png'),
  SeerrBrand(id: 1024, name: 'Prime Video', logoPath: '/ifhbNuuVnlwYy5oXA5VIb2YR8AZ.png'),
  SeerrBrand(id: 2552, name: 'Apple TV+', logoPath: '/4KAy34EHvRM25Ih8wb82AuGU7zJ.png'),
  SeerrBrand(id: 453, name: 'Hulu', logoPath: '/pqUTCleNUiTLAVlelGxUgWn1ELh.png'),
  SeerrBrand(id: 49, name: 'HBO', logoPath: '/tuomPhY2UtuPTqqFnKMVHvSb724.png'),
  SeerrBrand(id: 4353, name: 'Discovery+', logoPath: '/1D1bS3Dyw4ScYnFWTlBOvJXC3nb.png'),
  SeerrBrand(id: 2, name: 'ABC', logoPath: '/ndAvF4JLsliGreX87jAc9GdjmJY.png'),
  SeerrBrand(id: 19, name: 'FOX', logoPath: '/1DSpHrWyOORkL9N2QHX7Adt31mQ.png'),
  SeerrBrand(id: 359, name: 'Cinemax', logoPath: '/6mSHSquNpfLgDdv6VnOOvC5Uz2h.png'),
  SeerrBrand(id: 174, name: 'AMC', logoPath: '/pmvRmATOCaDykE6JrVoeYxlFHw3.png'),
  SeerrBrand(id: 67, name: 'Showtime', logoPath: '/Allse9kbjiP6ExaQrnSpIhkurEi.png'),
  SeerrBrand(id: 318, name: 'Starz', logoPath: '/8GJjw3HHsAJYwIWKIPBPfqMxlEa.png'),
  SeerrBrand(id: 71, name: 'The CW', logoPath: '/ge9hzeaU7nMtQ4PjkFlc68dGAJ9.png'),
  SeerrBrand(id: 6, name: 'NBC', logoPath: '/o3OedEP0f9mfZr33jz2BfXOUK5.png'),
  SeerrBrand(id: 16, name: 'CBS', logoPath: '/nm8d7P7MJNiBLdgIzUK0gkuEA4r.png'),
  SeerrBrand(id: 4330, name: 'Paramount+', logoPath: '/fi83B1oztoS47xxcemFdPMhIzK.png'),
  SeerrBrand(id: 4, name: 'BBC One', logoPath: '/mVn7xESaTNmjBUyUtGNvDQd3CT1.png'),
  SeerrBrand(id: 56, name: 'Cartoon Network', logoPath: '/c5OC6oVCg6QP4eqzW6XIq17CQjI.png'),
  SeerrBrand(id: 80, name: 'Adult Swim', logoPath: '/9AKyspxVzywuaMuZ1Bvilu8sXly.png'),
  SeerrBrand(id: 13, name: 'Nickelodeon', logoPath: '/ikZXxg6GnwpzqiZbRPhJGaZapqB.png'),
  SeerrBrand(id: 3353, name: 'Peacock', logoPath: '/gIAcGTjKKr0KOHL5s4O36roJ8p7.png'),
];
